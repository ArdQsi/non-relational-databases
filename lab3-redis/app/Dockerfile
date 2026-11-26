FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
ENV PROMETHEUS_MULTIPROC_DIR=/tmp/prom
ENV WORKERS=4
# каталог multiprocess-метрик очищается при каждом старте контейнера
CMD ["sh", "-c", "rm -rf $PROMETHEUS_MULTIPROC_DIR && mkdir -p $PROMETHEUS_MULTIPROC_DIR && exec uvicorn main:app --host 0.0.0.0 --port 8000 --workers $WORKERS"]
