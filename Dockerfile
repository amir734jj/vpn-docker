FROM garfieldwtf/openvpn

COPY entrypoint.sh /usr/local/bin/auto-entrypoint.sh
RUN chmod +x /usr/local/bin/auto-entrypoint.sh

# Base image has no ENTRYPOINT, only CMD ["ovpn_run"]
# Override CMD to use our auto-init wrapper
CMD ["/usr/local/bin/auto-entrypoint.sh"]
