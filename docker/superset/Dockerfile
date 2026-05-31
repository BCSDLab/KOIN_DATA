FROM apache/superset:4.0.2

USER root
COPY docker/superset/requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
USER superset
