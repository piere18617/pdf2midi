# pdf2music

Convert a PDF music score into **MusicXML** and/or **MIDI**, fully offline,
using a state-of-the-art Optical Music Recognition (OMR) engine.

The OMR backend is [`homr`](https://github.com/liebharc/homr) — a two-stage
deep-learning system (UNet segmentation + transformer symbol recognition, based
on Polyphonic-TrOMR) that runs entirely on-device. On Apple Silicon the
segmentation model automatically uses the CoreML execution provider for speed;
no GPU/CUDA or cloud services are required. MIDI conversion is done with
[`music21`](https://web.mit.edu/music21/).

It is tuned for **digitally generated** PDF scores (vector content), where it
performs best, but it also handles photos/scans thanks to homr's built-in
deskew/dewarp and autocrop.

## Install

Requires [Python 3.11+](https://www.python.org/) and
[uv](https://docs.astral.sh/uv/) (recommended). `uv` automatically manages a
isolated Python 3.11 environment, so your system Python version does not
matter.

```bash
git clone <this-repo> pdf2music
cd pdf2music
uv sync
```

Model weights (~110 MB: segnet + transformer encoder/decoder, plus an OCR model
for title detection) are downloaded automatically on the **first run** and
cached inside the venv. To pre-fetch them without running a conversion:

```bash
uv run homr --init
```

## Usage

```bash
# Convert a PDF, writing both .musicxml and .mid next to the input file
uv run pdf2music "path/to/score.pdf"

# Write outputs to a specific directory, MIDI only
uv run pdf2music score.pdf -o ./out -f midi

# Higher DPI render (helps for small/vector PDFs)
uv run pdf2music score.pdf --dpi 500

# Add a metronome marking and open the output folder in Finder
uv run pdf2music score.pdf --metronome 120 --open

# Also accept a PNG/JPG image instead of a PDF
uv run pdf2music scan.jpg --format musicxml
```

### Options

| Flag | Description |
| --- | --- |
| `-o, --output DIR` | Output directory (default: next to input). |
| `-f, --format {musicxml,midi,both}` | Output format (default: `both`). |
| `--dpi N` | DPI for PDF→image rendering (default: `300`). |
| `--coreml-encoder` | On Apple Silicon, run the transformer encoder on GPU via CoreML. Slow one-time compile (~30–60 s); only pays off across many images. |
| `--metronome BPM` | Add a metronome marking to the MusicXML. |
| `--keep-png` | Keep the intermediate rendered PNG. |
| `--debug` | Enable homr debug output (extra debug images). |
| `--open` | Open the output directory in Finder when done. |

You can also use it as a module: `uv run python -m pdf2music score.pdf`.

### Make it a global command

```bash
uv tool install .
pdf2music score.pdf
```

## Web version

`webapp/` is a browser port of the same pipeline: the OMR runs entirely
client-side on ONNX Runtime Web (wasm) and OpenCV.js, so no server does any of
the work.

```bash
cd webapp
npm install
npm run dev
```

Drop a PDF on the page; it renders the pages with pdf.js, runs segmentation and
the transformer in a web worker, and offers the MusicXML and MIDI as downloads.
The ONNX weights (~125 MB) are downloaded on first use and cached in IndexedDB.

Note that homr publishes its weights as GitHub release assets, which are served
without CORS headers and so cannot be fetched cross-origin from a page. The dev
and preview servers therefore proxy them under `/models/` (see
`webapp/vite.config.ts`). For a static deployment, host the model zips yourself
and point `VITE_MODEL_BASE_URL` at them:

```bash
VITE_MODEL_BASE_URL=https://your-host/models/ npm run build
```

Being single-threaded wasm, the browser version is several times slower than
the CLI, and it omits the CLI's title detection.

### Container

Tagged releases publish a multi-arch image (amd64 + arm64) to GHCR:

```bash
docker run --rm -p 8080:80 ghcr.io/pllopis/pdf2music:latest
```

The image is the built bundle served by nginx, which also proxies `/models/`
through to the homr release assets so the browser can fetch the weights (they
are served without CORS headers, see above). To use your own mirror instead,
build with `--build-arg VITE_MODEL_BASE_URL=https://your-host/models/`.

Pushing a semver tag (`v1.2.3`) builds and pushes the image tagged with that
version and, for non-prereleases, `latest` — see
`.github/workflows/release.yml`.

### Ties

homr's transformer has no tie tokens in its vocabulary, so a tie is recognised
as a slur. The web version turns a slur joining two adjacent notes of the same
pitch — which is what a tie is — into a real tie, emitting both `<tie>` and
`<tied>` in the MusicXML and merging the notes in the MIDI. It is a heuristic,
but a curved line between two identical adjacent pitches is not notated as
anything else. The CLI does not do this, so its output still renders ties as
separate slurred notes.

## How it works

1. **PDF → PNG** (`pdf_render.py`): every page is rendered with `pypdfium2` at
   the requested DPI, autocropped, and vertically stacked into one image —
   matching homr's own multi-page handling.
2. **PNG → MusicXML** (`omr.py`): homr's public CLI entry point is invoked
   in-process (same interpreter/venv). homr dewarps the staffs, runs the segnet
   segmentation model, merges grand staves, then runs the transformer encoder
   + decoder to produce a symbol sequence, which is serialized to MusicXML.
3. **MusicXML → MIDI** (`midi_convert.py`): `music21` parses the MusicXML and
   writes a standard `.mid` file.

Intermediate files are written to a temporary directory and only the requested
outputs are copied to the final location.

## Limitations

- OMR is imperfect: expect some errors in rhythm, accidentals, and articulations
  — especially on dense or unusual notation. Homr focuses on pitch and rhythm
  on treble/bass clefs and intentionally omits dynamics, double sharps/flats, and
  some other symbols.
- The first run downloads model weights (one-time).
- Multi-page PDFs are stacked into a single image, so very long scores are
  processed as one piece.

## License

This project wraps `homr` (AGPL-3.0) and `music21` (BSD-3-Clause). Source files
in this repository are released under AGPL-3.0 to match homr's license.
