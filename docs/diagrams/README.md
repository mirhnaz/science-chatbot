# Curio classroom diagram

A classroom walkthrough of the current project, suitable for a child explaining
it to a teacher. Follow the numbered arrows across the top, down the right, and
back along the bottom. The dashed arrow starts another question.

- [Presentation image](curio-workflow.png): 2880 × 1800 PNG; insert it
  into a slide or print it in landscape orientation, fitted to the page.
- [Editable diagram](curio-workflow.svg): scalable vector drawing with
  editable text and shapes. Open it in a vector editor or browser. It uses Noto
  Sans with a generic sans-serif fallback; text appearance may vary by computer.

## Speaking notes: about two minutes

**Introduction:** “Our project, Curio, is a science chatbot for children. You can ask a
science question and get an explanation plus three new questions to explore.
The blue area is the screen we use. The green area shows what happens on our
home computer.”

1. **Ask a question.** “I open the website on a phone or computer, type a question,
   or choose a starter topic, and press Ask. For example: Why is the sky blue?”
2. **Check the question.** “The question travels through an encrypted internet
   connection. Our app checks that it is not empty or too long.”
3. **Add tutor instructions.** “We give the AI instructions to explain science
   kindly, use an everyday example, and suggest safe ideas for children. These
   instructions guide its answer.”
4. **AI writes a reply.** “The AI is called Qwen. A program called Ollama runs it
   on our home computer. It uses what it learned during training to create an
   answer and three follow-up questions. Our app does not search the web for
   each answer.”
5. **Check the reply.** “Our app checks that an answer and three different
   follow-up questions came back in the right format. That does not prove that
   every fact is right, so I still check important facts with my teacher.”
6. **Read and explore.** “The answer appears on my screen. I can click a follow-up
   to explore further. That sends a new question, so we go around the diagram
   again. Each question starts fresh.”

**Finish:** “I can also listen to the answer if my browser supports Read aloud,
stop while I am waiting, or try again if something goes wrong. We would like to
add accounts and saved conversations in the future, but they are not part of
this version.”

## Questions the teacher might ask

- **Did you train the AI?** No. Qwen is an existing model developed by Alibaba
  Cloud. Ayaan and Naz Mir created this app and its tutor instructions.
- **Does the AI run on the phone?** No. The phone shows the website; the home
  computer runs the app and AI tutor.
- **Is the AI always correct or safe?** No. Instructions guide it, but they do
  not guarantee correctness or safety. Ask a teacher or adult when unsure.
- **Does it remember the conversation?** Not in this version. Each request sends
  the new question and tutor instructions; the app does not save chat history.
- **What is Rust?** The programming language used for the part of our app that
  handles questions and communicates with the AI tutor. The browser interface
  is written in TypeScript, which is built into JavaScript for the browser.

## Editing and verification

The SVG is the editable source; the PNG is its rendered copy. To regenerate the
PNG with the existing system renderer:

```sh
rsvg-convert -w 2880 -h 1800 -o docs/diagrams/curio-workflow.png docs/diagrams/curio-workflow.svg
```

The exported image was visually checked for readable labels, arrow direction,
spacing, and clipping. The diagram describes the current app, not the proposed
login/history features. It changes no application code or deployed settings.
