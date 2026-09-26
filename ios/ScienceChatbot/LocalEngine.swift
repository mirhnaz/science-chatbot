import Foundation
import llama
import ScienceCore

/// Runs a GGUF model inside the app with llama.cpp, fully offline.
///
/// An `actor` lets only one task use it at a time. That matters because a
/// llama.cpp context is not thread-safe, and it plays the role of the server's
/// request permits: one question generates at a time on the iPad.
actor LocalEngine {
    static let shared = LocalEngine()

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var loadedPath: String?

    private let contextSize: UInt32 = 4096
    private let maxReplyTokens = 1024
    private let deadline: TimeInterval = 120

    private init() {
        llama_backend_init()
    }

    /// Loads the model file once and keeps it in memory for later questions.
    func load(path: String) throws {
        if loadedPath == path, context != nil { return }
        unload()

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 999  // put every layer on the Metal GPU
        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw TutorError.message(
                "The science model could not be loaded. Try a smaller model in Settings.")
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = contextSize
        contextParams.n_batch = contextSize
        let cores = ProcessInfo.processInfo.activeProcessorCount
        contextParams.n_threads = Int32(max(1, cores - 2))
        contextParams.n_threads_batch = Int32(max(1, cores - 2))
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw TutorError.message("There is not enough memory for this model. Try a smaller model.")
        }
        self.model = model
        self.context = context
        loadedPath = path
    }

    func unload() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        loadedPath = nil
    }

    func ask(_ question: String, modelPath: String) throws -> TutorReply {
        try load(path: modelPath)
        guard let model, let context else { throw TutorError.message("No model is loaded.") }
        let vocab = llama_model_get_vocab(model)
        let started = Date()

        // Each question is independent, like the server: forget the last one.
        llama_memory_clear(llama_get_memory(context), true)

        var tokens = tokenize(vocab: vocab, text: prompt(model: model, question: question))
        guard !tokens.isEmpty, tokens.count < Int(contextSize) - maxReplyTokens else {
            throw TutorError.message(ValidationError.questionTooLong.description)
        }

        guard let sampler = makeSampler(vocab: vocab) else {
            throw TutorError.message("The answer format could not be prepared.")
        }
        defer { llama_sampler_free(sampler) }

        let promptStatus = tokens.withUnsafeMutableBufferPointer {
            llama_decode(context, llama_batch_get_one($0.baseAddress, Int32($0.count)))
        }
        guard promptStatus == 0 else { throw TutorError.message("The model could not read the question.") }

        // Collect raw bytes and decode UTF-8 once at the end, because one
        // emoji or accented letter can be split across several tokens.
        var output: [UInt8] = []
        for _ in 0..<maxReplyTokens {
            try Task.checkCancellation()
            if Date().timeIntervalSince(started) > deadline { throw TutorError.timedOut }

            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            output += piece(vocab: vocab, token: token)

            let status = llama_decode(context, llama_batch_get_one(&token, 1))
            guard status == 0 else { throw TutorError.message("The model stopped unexpectedly.") }
        }

        do {
            return try decodeReply(String(decoding: output, as: UTF8.self))
        } catch let error as ValidationError {
            throw TutorError.message(error.description)
        }
    }

    // MARK: - Helpers

    /// Formats system + user messages with the model's own chat template.
    private func prompt(model: OpaquePointer, question: String) -> String {
        let system = BundledText.tutorPrompt
        if let template = llama_model_chat_template(model, nil) {
            let roles = [strdup("system"), strdup("user")]
            let contents = [strdup(system), strdup(question)]
            defer { (roles + contents).forEach { free($0) } }
            var messages = [
                llama_chat_message(role: roles[0], content: contents[0]),
                llama_chat_message(role: roles[1], content: contents[1]),
            ]
            var buffer = [CChar](repeating: 0, count: (system.utf8.count + question.utf8.count) * 2 + 256)
            var length = llama_chat_apply_template(template, &messages, 2, true, &buffer, Int32(buffer.count))
            if length > buffer.count {
                buffer = [CChar](repeating: 0, count: Int(length) + 1)
                length = llama_chat_apply_template(template, &messages, 2, true, &buffer, Int32(buffer.count))
            }
            if length > 0 {
                return String(decoding: buffer[0..<Int(length)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        // Qwen models use the ChatML layout if the template is unavailable.
        return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(question)<|im_end|>\n<|im_start|>assistant\n"
    }

    private func tokenize(vocab: OpaquePointer?, text: String) -> [llama_token] {
        let count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(count) + 8)
        var n = llama_tokenize(vocab, text, count, &tokens, Int32(tokens.count), true, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, count, &tokens, Int32(tokens.count), true, true)
        }
        return n > 0 ? Array(tokens.prefix(Int(n))) : []
    }

    private func piece(vocab: OpaquePointer?, token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if n < 0 {
            buffer = [CChar](repeating: 0, count: Int(-n))
            n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(n, 0))).map { UInt8(bitPattern: $0) }
    }

    /// Grammar first, so only JSON matching the reply schema can be chosen;
    /// then Qwen's recommended non-thinking sampling settings.
    private func makeSampler(vocab: OpaquePointer?) -> UnsafeMutablePointer<llama_sampler>? {
        guard let grammar = llama_sampler_init_grammar(vocab, replyGrammar, "root") else { return nil }
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(chain, grammar)
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(20))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.8, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        return chain
    }
}

/// Adapts the shared actor to the TutorEngine protocol for one model file.
struct LocalTutor: TutorEngine {
    let modelPath: String

    func ask(_ question: String) async throws -> TutorReply {
        try await LocalEngine.shared.ask(question, modelPath: modelPath)
    }
}
