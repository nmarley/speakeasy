FROM debian:bookworm-slim
RUN apt update && apt install -y librsvg2-bin
WORKDIR /app
COPY svg-to-xcassets.sh /
COPY svg-to-favicons.sh /
RUN chmod +x /svg-to-xcassets.sh
RUN chmod +x /svg-to-favicons.sh
ENTRYPOINT ["/svg-to-xcassets.sh"]
CMD ["/bin/sh"]
