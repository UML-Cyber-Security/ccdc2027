#!/bin/sh

# ---------- root check ----------
# $EUID is bash-only; id -u is POSIX
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root" >&2
    exit 1
fi

# ---------- hashing helper ----------
# Reads stdin, prints the lowercase SHA-256 hex digest.
# Falls back to sha256sum/sha256 since Alpine doesn't ship the openssl CLI by default.
sha256_hex() {
    if command -v openssl >/dev/null 2>&1; then
        # OpenSSL 1.1, OpenSSL 3 and LibreSSL all print the digest as the last field
        openssl dgst -sha256 | awk '{print $NF}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v sha256 >/dev/null 2>&1; then
        sha256 -q
    else
        return 1
    fi
}

if ! command -v openssl >/dev/null 2>&1 &&
   ! command -v sha256sum >/dev/null 2>&1 &&
   ! command -v sha256 >/dev/null 2>&1; then
    echo "No SHA-256 tool found (need openssl, sha256sum, or sha256)" >&2
    exit 1
fi

# ---------- read master hash silently ----------
# read -s and read -p are bash-only; use stty to turn off echo instead
if [ -t 0 ]; then
    printf 'Enter master hash: '
    trap 'stty echo' EXIT
    trap 'stty echo; exit 1' INT TERM
    stty -echo
    read -r MASTER_HASH
    stty echo
    trap - EXIT INT TERM
    printf '\n'
else
    read -r MASTER_HASH
fi

if [ -z "$MASTER_HASH" ]; then
    echo "Master hash cannot be empty" >&2
    exit 1
fi

# ---------- OS detection ----------
# == is a bashism; POSIX test uses =
if [ "$(uname)" = "FreeBSD" ]; then
    OS="freebsd"
elif [ -f /etc/os-release ]; then
    # Source in a subshell so os-release's variables don't leak into the script
    OS=$(. /etc/os-release && printf '%s' "$ID")
else
    OS="unknown"
fi

# ---------- password change ----------
# POSIX has no 'local', so function variables are prefixed with cp_
# to avoid clobbering anything in the caller (like $username in the loop)
change_password() {
    cp_user=$1

    # [[ == pattern ]] is a bashism; case does glob matching in POSIX
    case $cp_user in
        ccdc*|ccsi*)    # exclude accounts like blackteam here
            echo "Skipped: $cp_user"
            return 0
            ;;
    esac

    # printf '%s\n' reproduces echo's trailing newline exactly,
    # so derived passwords match the original bash script
    cp_pass=$(printf '%s\n' "$MASTER_HASH:$cp_user" | sha256_hex | cut -c1-16)

    if [ -z "$cp_pass" ]; then
        echo "Failed (hash error): $cp_user" >&2
        return 1
    fi

    if [ "$OS" = "freebsd" ]; then
        printf '%s\n' "$cp_pass" | pw usermod "$cp_user" -h 0
        cp_rc=$?
    else
        printf '%s:%s\n' "$cp_user" "$cp_pass" | chpasswd
        cp_rc=$?
    fi

    if [ "$cp_rc" -eq 0 ]; then
        echo "Changed: $cp_user"
    else
        echo "Failed: $cp_user" >&2
    fi
    sleep 2
}

change_password "root"

while IFS=: read -r username _ uid _ _ _ shell; do
    # Skip comment lines, NIS '+' entries, and anything with a non-numeric UID
    case $uid in
        ''|*[!0-9]*) continue ;;
    esac

    [ "$uid" -ge 1000 ] || continue

    case $shell in
        */nologin|*/false) continue ;;
    esac

    change_password "$username"
done < /etc/passwd