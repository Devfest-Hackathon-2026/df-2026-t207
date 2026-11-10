FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    MODELS_DIR=/models \
    U2NET_HOME=/models/u2net \
    HF_HOME=/models/hf \
    HF_HUB_DISABLE_TELEMETRY=1 \
    PIP_NO_CACHE_DIR=1 \
    NUMBA_CPU_NAME=generic
# NUMBA_CPU_NAME: rembg が import する pymatting は import の時に numba で約 40 秒かけて翻訳し、結果をキャッシュに置く。
# キャッシュは CPU の型が完全に一致しないと使われず、Cloud Build と Cloud Run の CPU は違うので、0 台からの起動の度に
# 翻訳し直していた (2026-11-08 に Cloud Build で実測: キャッシュが外れて 40.4 秒、当たって 1.1 秒)。generic で CPU に依らない物にする
# (https://numba.readthedocs.io/en/stable/reference/envvars.html 。pymatting の関数は only_mask の処理では呼ばない)

RUN apt-get update \
    && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
    && apt-get clean

WORKDIR /app
RUN pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
COPY requirements.txt .
# transformers は import の度に models/ の下の全部のモデルの .py (約 2500 個) を読んで中身を調べる。
# 0 台からの起動ではファイルを 1 つ読むごとに待つので、SAM 2.1 で使う物の他を消す (同じ RUN で消さないとイメージが縮まない)。
# 残す物は SAM の読み込みと推論を通して sys.modules に出た物 (auto・encoder_decoder・sam2) と、sam2 の元になった物。
# vision で別の Hugging Face のモデルを使う時は、その model_type をこの一覧に足す (足さないとイメージの中だけで import が落ちる)
RUN pip install -r requirements.txt \
    && cd "$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')/transformers/models" \
    && ls | grep -vxE 'auto|encoder_decoder|sam|sam2|sam2_video|detr|vitdet|__init__\.py|__pycache__' | xargs rm -rf

# 重み (isnet・SAM 2.1・YuNet) は cloudbuild.yaml の最初の段が Storage の build-models/ から ./models に落とす
# (GitHub の配布が 504 でビルドが落ちたため、2026-11-08 に置いた)。無い物と hash の違う物は fetch_models.py が取り直す
COPY models /models
COPY fetch_models.py .
RUN python fetch_models.py

COPY main.py masking.py pipeline.py models.py selfcheck.py ./
ENV HF_HUB_OFFLINE=1
# 実際の処理の道 (背景を消す・顔を探す・SAM の点と枠の切り抜き) を一通り通して確かめる。壊れていればビルドが落ちる。
# 起動の時の先読みは測って外した (2026-11-08: 先読みありで 36.4 秒、なしで 26.2 秒)
RUN python selfcheck.py
CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080} --workers 1
