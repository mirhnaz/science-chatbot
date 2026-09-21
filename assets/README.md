# App icon

`science-chatbot-icon.png` is the user-provided science flask artwork.
ImageMagick resized the full square composition without cropping into:

- `public/favicon.ico`: 16, 32, and 48 pixels.
- `public/favicon-32.png`: 32 pixels.
- `public/apple-touch-icon.png`: 180 pixels for iPhone/iPad home-screen use.
- `public/icon-192.png` and `public/icon-512.png`: web app manifest icons.

The original artwork is preserved in the master image. Devices apply their own
home-screen corner masks. Icon URLs include a version query to refresh browser
caches when replacing the previous artwork.
