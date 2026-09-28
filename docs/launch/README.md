# Curio launch video

[curio-launch.mp4](curio-launch.mp4): 54 s, 1920 × 1080, 30 fps, H.264 + AAC.

Storyboard: a pixel night sky with a comet ("Every kid has big questions")
and real sparks floating up; the app icon reveal as the sky turns to day;
real iPad screens (Home with a spark circled, a Trail answer, Dive deeper
choices, Trail complete with the stamp burst, Stamps); five trail steps;
laptop, iPad and iPhone together (voice, read aloud, light and dark);
"Runs on our own computer. No ads. No accounts."; end card with the
tagline and "Made with love by Ayaan and Naz".

The screens in `shots/` are real screenshots of the web app (iPad, phone
and laptop sizes) holding a five-step comet trail answered by the live
tutor (Gemma 4) on 2026-09-28. No voice-over; a narration could be
recorded and mixed in later.

## Rebuild

```sh
python3 make-music.py      # writes music.wav (generated, no licence needed)
node render-video.mjs      # renders launch-video.html frame by frame, then ffmpeg
```

Needs Google Chrome and ffmpeg. `launch-video.html` also plays in real time
when opened in a browser. Edit captions and timings there (`render(t)`).
