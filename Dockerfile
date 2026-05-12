FROM dart:stable AS build

WORKDIR /app
COPY pubspec.yaml .
RUN dart pub get

COPY . .
RUN dart compile exe bin/servidor.dart -o bin/servidor_bin

FROM debian:bullseye-slim
WORKDIR /app
COPY --from=build /app/bin/servidor_bin /app/bin/servidor_bin

RUN chmod +x /app/bin/servidor_bin

EXPOSE 8080
CMD ["/app/bin/servidor_bin"]
