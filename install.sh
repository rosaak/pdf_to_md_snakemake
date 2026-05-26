# 1. store the Snakefile
mkdir -p ~/.config/pdf-to-md
cp Snakefile ~/.config/pdf-to-md/Snakefile

# 2. create a uv virtual env and install libraries
mkdir -p ~/.venvs && cd ~/.venvs/
uv venv uv-pdf-to-md-sm
source ~/.venvs/uv-pdf-to-md-sm/bin/activate

uv pip install "docling[asr,vlm,easyocr,tesserocr,ocrmac,htmlrender,rapidocr]"
uv pip install "snakemake"
deactivate
cd -

# 3. create the wrapper
mkdir -p ~/.local/bin
cat >~/.local/bin/pdf2md-sm <<'EOF'
#!/bin/bash
source ~/.venvs/uv-pdf-to-md-sm/bin/activate
snakemake \
    --snakefile ~/.config/pdf-to-md/Snakefile \
    --cores ${CORES:-4} \
    --latency-wait 10 \
    "$@"
EOF
chmod +x ~/.local/bin/pdf2md-sm
