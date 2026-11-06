FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN pip install --no-cache-dir gunicorn==26.2.0 pywebpush==2.5.0 && useradd --uid 10001 --create-home tolk
WORKDIR /app
COPY server /app/server
COPY public /app/public
RUN mkdir /data && chown tolk:tolk /data
USER tolk
WORKDIR /app/server
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--threads", "4", "--timeout", "30", "--access-logfile", "/dev/null", "--error-logfile", "-", "wsgi:production_app()"]
