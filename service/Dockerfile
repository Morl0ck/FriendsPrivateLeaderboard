FROM golang:1.23-alpine AS builder
WORKDIR /src/app

# Install CA certificates for modules fetch
RUN apk add --no-cache ca-certificates tzdata git

# Cache modules first based on go.mod/go.sum
COPY ./app/go.mod ./app/go.sum ./
RUN go mod download

# Copy sources and finalize module graph (adds indirect deps to go.sum)
COPY ./app/ ./
RUN go mod tidy

# Build static binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o /out/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && adduser -D -H -u 10001 app
USER app
WORKDIR /home/app
COPY --from=builder /out/server /home/app/server
EXPOSE 8080
ENV PORT=8080
ENTRYPOINT ["/home/app/server"]
