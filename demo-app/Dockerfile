# syntax=docker/dockerfile:1
FROM golang:1.27.1-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go test ./...

ARG VERSION=dev
ARG COMMIT=unknown
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath \
      -ldflags="-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" \
      -o /out/demo-app .

FROM scratch
COPY --from=build /out/demo-app /demo-app
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/demo-app"]
