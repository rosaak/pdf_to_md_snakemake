# Snakefile
import glob
import os
import shutil
from pathlib import Path

# ── Step 0 : sanitize PDF filenames before DAG is built ──────────────────────

for f in Path(".").glob("*.PDF"):
    renamed = f.with_suffix(".pdf")
    print(f"Normalizing extension: {f.name!r} → {renamed.name!r}")
    f.rename(renamed)

def sanitize(name: str) -> str:
    # replace anything that's not alphanumeric, dash, underscore, or dot
    return re.sub(r"[^\w\-.]", "_", name)

for pdf in Path(".").glob("*.pdf"):
    clean = sanitize(pdf.stem) + ".pdf"
    if clean != pdf.name:
        print(f"Renaming: {pdf.name!r} → {clean!r}")
        pdf.rename(clean)

# ── Discover PDFs ─────────────────────────────────────────────────────────────
PDFS      = glob.glob("*.pdf")
BASENAMES = [os.path.splitext(f)[0] for f in PDFS]

if not BASENAMES:
    raise WorkflowError("No .pdf files found in the current directory.")


# ── Named target : full pipeline ──────────────────────────────────────────────
rule all:
    input:
        "artifacts_removed.done"


# ── Named target : convert only, no path rewriting, no image moving ───────────
rule convert_pdf_to_md:
    input:
        expand("{basename}.md", basename=BASENAMES)


# ── Rule 1 : PDF → Markdown via Docling Python API ───────────────────────────
rule pdf_to_markdown:
    input:
        pdf = lambda wc: wc.basename + ".pdf"
    output:
        md  = "{basename}.md"
    log:
        "logs/{basename}.docling.log"
    threads: 4
    run:
        import logging
        from pathlib import Path
        from docling.document_converter import DocumentConverter, PdfFormatOption
        from docling.datamodel.base_models import InputFormat
        from docling.datamodel.pipeline_options import (
            PdfPipelineOptions,
            AcceleratorOptions,
            AcceleratorDevice,
        )
        from docling_core.types.doc.document import ImageRefMode

        os.makedirs("logs", exist_ok=True)

        # ── log to file ───────────────────────────────────────────────────────
        log_path = log[0]
        logger   = logging.getLogger()
        handler  = logging.FileHandler(log_path, mode="a")
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)

        # ── relative paths so markdown image refs are not absolute ────────────
        pdf_path      = Path(input.pdf).resolve()   # absolute only for converter input
        out_md        = Path(output.md)              # relative → clean image refs
        artifacts_dir = Path(wildcards.basename + "_artifacts")  # relative

        # ── force CPU to avoid MPS float64 crash on Apple Silicon ────────────
        pipeline_opts = PdfPipelineOptions()
        pipeline_opts.accelerator_options = AcceleratorOptions(
            device=AcceleratorDevice.CPU
        )
        pipeline_opts.generate_picture_images = True
        pipeline_opts.images_scale            = 2.0

        converter = DocumentConverter(
            format_options={
                InputFormat.PDF: PdfFormatOption(
                    pipeline_options=pipeline_opts
                )
            }
        )

        print(f"Converting {pdf_path} ...")
        result = converter.convert(str(pdf_path))

        # ── write markdown + images if any ────────────────────────────────────
        # artifacts_dir is only created by docling if the PDF contains images
        result.document.save_as_markdown(
            filename      = out_md,
            artifacts_dir = artifacts_dir,
            image_mode    = ImageRefMode.REFERENCED,
        )

        print(f"Written:  {out_md}")
        if artifacts_dir.exists():
            png_count = len(list(artifacts_dir.glob("*.png")))
            print(f"Images:   {artifacts_dir}/ ({png_count} PNGs)")
        else:
            print(f"No images found in {pdf_path.name}")


# ── Rule 2 : rewrite artifact paths, move PNGs → images/ ─────────────────────
rule fix_artifact_paths:
    input:
        md  = "{basename}.md"
    output:
        done = "{basename}.md.done"
    run:
        src           = Path(input.md)
        artifacts_dir = Path(wildcards.basename + "_artifacts")
        images_dir    = Path("images")
        old_path      = wildcards.basename + "_artifacts"
        new_path      = "images"

        # ── rewrite paths in .md ──────────────────────────────────────────────
        content = src.read_text(encoding="utf-8")
        n       = content.count(old_path)
        if n > 0:
            images_dir.mkdir(exist_ok=True)
            src.write_text(content.replace(old_path, new_path), encoding="utf-8")
            print(f"  {src}: replaced {n} occurrence(s) of '{old_path}' → '{new_path}'")
        else:
            print(f"  {src}: no artifact path references found, skipping rewrite")

        # ── move PNGs if _artifacts/ exists ───────────────────────────────────
        if artifacts_dir.exists():
            images_dir.mkdir(exist_ok=True)
            moved = []
            for png in artifacts_dir.glob("*.png"):
                dest = images_dir / png.name
                if dest.exists():
                    dest = images_dir / f"{png.stem}__{artifacts_dir.name}{png.suffix}"
                shutil.move(str(png), str(dest))
                moved.append(f"  {png} → {dest}")
            if moved:
                print("Moved PNGs:\n" + "\n".join(moved))
        else:
            print(f"  No _artifacts/ dir for {src.name}, nothing to move")

        # ── touch sentinel ────────────────────────────────────────────────────
        Path(output.done).touch()


# ── Rule 3 : remove empty *_artifacts dirs and all sentinels ─────────────────
rule collect_and_clean:
    input:
        expand("{basename}.md.done", basename=BASENAMES)
    output:
        touch("artifacts_removed.done")
    run:
        # Step 1 — remove empty *_artifacts dirs
        for entry in os.scandir("."):
            if entry.is_dir() and entry.name.endswith("_artifacts"):
                try:
                    os.rmdir(entry.path)
                    print(f"  Removed dir: {entry.name}")
                except OSError:
                    print(f"  Skipping non-empty dir: {entry.name}")

        # Step 2 — remove all .md.done sentinels
        removed = []
        for done_file in Path(".").glob("*.md.done"):
            done_file.unlink()
            removed.append(str(done_file))
        if removed:
            print("Removed sentinels:\n" + "\n".join(f"  {f}" for f in removed))
