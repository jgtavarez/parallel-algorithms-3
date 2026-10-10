FROM rust:1.85 AS build
WORKDIR /app
COPY . .
RUN cargo build --release --locked

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /app/target/release/api /usr/local/bin/api
EXPOSE 3000
CMD ["api"]
