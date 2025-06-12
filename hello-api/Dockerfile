FROM python:3-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install additional deb packages
RUN apt-get update -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /code

# Create and use a non-root user
RUN groupadd -g 1000 slytherin \
    && useradd -u 1000 -g 1000 -s /bin/bash -m slytherin \
    && chown -R 1000:1000 /code
USER slytherin

ENV PATH="/home/slytherin/.local/bin:${PATH}"

COPY --chown=1000:1000 requirements.txt .
RUN pip install --user --upgrade pip \
    && pip install --user -r requirements.txt

COPY --chown=1000:1000 app.py .

EXPOSE 8000

CMD [ "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000" ]
