FROM dart:stable

WORKDIR /app
COPY pubspec.yaml .
RUN dart pub get --no-precompile

COPY . .

EXPOSE 8080
CMD ["dart", "run", "bin/servidor.dart"]
