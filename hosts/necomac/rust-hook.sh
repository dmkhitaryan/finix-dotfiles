export NIX_CFLAGS_COMPILE="${NIX_CFLAGS_COMPILE:-} -mcpu=@cpu@"

case "${pname:-}" in
  rustc | rustc-unwrapped) ;;
  *) export RUSTFLAGS="${RUSTFLAGS:-} -C target-cpu=@cpu@" ;;
esac

unset doCheck doInstallCheck
