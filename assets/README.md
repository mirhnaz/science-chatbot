# App icon

`science-chatbot-icon.png` is the user-provided science flask artwork.
ImageMagick resized the full square composition without cropping into:

- `dist/favicon.ico`: 16, 32, and 48 pixels.
- `dist/favicon-32.png`: 32 pixels.
- `dist/apple-touch-icon.png`: 180 pixels for iPhone/iPad home-screen use.
- `dist/icon-192.png` and `dist/icon-512.png`: web app manifest icons.

The original artwork is preserved in the master image. Devices apply their own
home-screen corner masks. Icon URLs include a version query to refresh browser
caches when replacing the previous artwork.
