# Store art

These files are the art uploaded to the Creator Hub for Steal a Snackling.

| File | Where it's used |
|---|---|
| `game_icon.png` (512×512) | Places → Steal a Snackling → Icon |
| `thumbnail_1_belt.jpg` (1920×1080) | Thumbnails (Home Page and Experience Detail Page) |
| `thumbnail_2_snacklings.jpg` (1920×1080) | Thumbnails (Home Page and Experience Detail Page) |

The game pass and developer product icons are in `../store-icons/`.

## How they were made

1. Open the place in Studio and choose **Test → Start Test Session → Run**. This builds the world on a server with no player HUD.
2. Set up each shot from the command bar:
   - **Belt:** put Snacklings on the podiums and on the belt, then aim the camera from the lobby end, looking along the belt.
   - **Snacklings:** call `DevGallery.build()`, hide its name labels, and aim the camera at the front rows.
   - **Icon:** put three Snacklings on a small grass disc at y = 300, so only sky is behind them.
3. Capture the viewport, then add the titles with `python3 tools/store_art.py <icon|map|lineup> <capture> <out> [x0 y0 x1 y1]`.

Changes made during a Run session are thrown away when it stops, so the saved place is never touched.
