# PDF → Markdown Snakemake Pipeline

Converts a folder of PDF files to Markdown using [Docling](https://github.com/DS4SD/docling), extracts images, and consolidates everything into a clean `images/` directory.

## What it does

1. **Convert** — each `.pdf` is converted to `.md` via the Docling Python API, with embedded images saved to `<basename>_artifacts/`
2. **Rewrite** — image references inside each `.md` are rewritten from `<basename>_artifacts/` to `images/`
3. **Collect** — all `.png` files are moved into a single `images/` directory and the now-empty `*_artifacts/` dirs are removed

## Setup 01 

Requires Python 3.11+ and [uv](https://github.com/astral-sh/uv).

```bash
uv venv .venv && source .venv/bin/activate
uv sync
```

Or 

Run `install.sh` 


## Usage

### If installed via install.sh script

```bash
# check if the installation is correct
which pdf2md-sm

# dry run to preview the job graph
pdf2md-sm -n --printshellcmds
pdf2md-sm --dag | dot -Tpng > dag.png && open dag.png
pdf2md-sm --report report.html && open report.html

# run from anywhere 
pdf2md-sm
pdf2md-sm convert_pdf_to_md
pdf2md-sm --cores 4


```


### If not used install.sh 

Place your `.pdf` files in the working directory, then:

```bash
# dry-run to preview the job graph
snakemake -n

# run (adjust --cores to taste)
snakemake --cores 4


# run converts the pdfs to md and not cleanup afterwords
snakemake --cores 4 convert_only

```




## Output

```
.
├── APBio-Chap01.md                # converted markdown
├── APBio-Chap01.md
├── ...
├── images/                        # all extracted PNGs
│   ├── image_000000_5564e2....png
│   └── ...
└── logs/                          # per-PDF docling logs
    ├── APBio-Chap01.docling.log
    └── ...
```

Image references inside each `.md` look like:

```markdown
![Image](images/image_000000_985e0f50ea149caa....png)
```

## Notes

- **Apple Silicon** — the pipeline forces `AcceleratorDevice.CPU` to avoid a PyTorch MPS `float64` crash in the Docling layout model. This has no meaningful speed impact for typical document sizes.
- **Duplicate image names** — if two PDFs produce a PNG with the same filename, the second is renamed `<stem>__<source_dir>.png` rather than silently overwriting the first.
- **Partial failures** — if Docling fails on individual pages it logs warnings but still writes the `.md`; check `logs/` for details.
- **Re-running** — Snakemake tracks which `.md` files already exist and skips completed jobs. To force a full re-run: `snakemake --cores 4 --forceall`
