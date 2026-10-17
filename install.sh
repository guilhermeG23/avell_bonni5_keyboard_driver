#!/bin/sh
set -eu

PROGRAM=/usr/local/sbin/avell-kbd-backlight
WRAPPER=/usr/local/bin/avell-kbd-cycle
POLICY=/usr/share/polkit-1/actions/io.github.avell-kbd-backlight.policy
MODULE_CONF=/etc/modules-load.d/avell-kbd-backlight.conf
SERVICE=/etc/systemd/system/avell-kbd-backlight-restore.service
SLEEP_HOOK=/usr/lib/systemd/system-sleep/avell-kbd-backlight
STATE_DIR=/var/lib/avell-kbd-backlight

DEFAULT_SHORTCUT='<Super>F6'
SHORTCUT=$DEFAULT_SHORTCUT
INSTALL_SHORTCUT=1
HARDWARE_TEST=1
ACTION=install

usage() {
    cat <<EOF
Uso:
  sudo ./install.sh [--shortcut ATALHO] [--no-shortcut] [--no-hardware-test]
  sudo ./install.sh --uninstall

Opcoes:
  --shortcut ATALHO    Atalho do Cinnamon (padrao: $DEFAULT_SHORTCUT)
  --no-shortcut        Nao cria atalho no Cinnamon
  --no-hardware-test   Instala sem acender o teclado no nivel 1
  --uninstall          Remove os arquivos instalados por este projeto
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --shortcut)
            [ "$#" -ge 2 ] || { echo "Falta o valor de --shortcut." >&2; exit 2; }
            SHORTCUT=$2
            shift 2
            ;;
        --no-shortcut)
            INSTALL_SHORTCUT=0
            shift
            ;;
        --no-hardware-test)
            HARDWARE_TEST=0
            shift
            ;;
        --uninstall)
            ACTION=uninstall
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Opcao desconhecida: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "Execute como root: sudo ./install.sh" >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET_USER=${SUDO_USER:-}
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = root ] || ! id "$TARGET_USER" >/dev/null 2>&1; then
    TARGET_USER=
fi

configure_cinnamon_shortcut() {
    mode=$1

    if [ -z "$TARGET_USER" ]; then
        echo "Atalho do Cinnamon nao configurado: execute o instalador com sudo a partir da sessao grafica."
        return 0
    fi

    target_uid=$(id -u "$TARGET_USER")
    target_home=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    runtime_dir="/run/user/$target_uid"
    session_bus="/run/user/$target_uid/bus"
    if [ ! -S "$session_bus" ]; then
        echo "Atalho do Cinnamon nao configurado: sessao D-Bus de $TARGET_USER nao encontrada."
        return 0
    fi

    runuser -u "$TARGET_USER" -- \
        env HOME="$target_home" XDG_RUNTIME_DIR="$runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$session_bus" \
        python3 - "$mode" "$SHORTCUT" "$WRAPPER" <<'PY'
import ast
import subprocess
import sys

mode, shortcut, command = sys.argv[1:]
base_schema = "org.cinnamon.desktop.keybindings"
custom_schema = "org.cinnamon.desktop.keybindings.custom-keybinding"
base_path = "/org/cinnamon/desktop/keybindings/custom-keybindings"


def gsettings(*arguments: str) -> str:
    result = subprocess.run(
        ["gsettings", *arguments],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


raw_list = gsettings("get", base_schema, "custom-list")
if raw_list.startswith("@as "):
    raw_list = raw_list[4:]
custom_list = list(ast.literal_eval(raw_list))


def schema_for(name: str) -> str:
    return f"{custom_schema}:{base_path}/{name}/"


def read_string(schema: str, key: str) -> str:
    try:
        return str(ast.literal_eval(gsettings("get", schema, key)))
    except (ValueError, SyntaxError, subprocess.CalledProcessError):
        return ""


matching = [name for name in custom_list if read_string(schema_for(name), "command") == command]

if mode == "remove":
    for name in matching:
        schema = schema_for(name)
        for key in ("name", "command", "binding"):
            gsettings("reset", schema, key)
        custom_list.remove(name)
    gsettings("set", base_schema, "custom-list", repr(custom_list))
    raise SystemExit(0)

if matching:
    name = matching[0]
else:
    used = set(custom_list)
    index = 0
    while f"custom{index}" in used:
        index += 1
    name = f"custom{index}"
    custom_list.append(name)

schema = schema_for(name)
gsettings("set", schema, "name", repr("Avell - alternar iluminacao do teclado"))
gsettings("set", schema, "command", repr(command))
gsettings("set", schema, "binding", repr([shortcut]))
gsettings("set", base_schema, "custom-list", repr(custom_list))
PY
}

uninstall_project() {
    configure_cinnamon_shortcut remove || true
    systemctl disable --now avell-kbd-backlight-restore.service >/dev/null 2>&1 || true
    rm -f "$PROGRAM" "$WRAPPER" "$POLICY" "$MODULE_CONF" "$SERVICE" "$SLEEP_HOOK"
    rm -rf "$STATE_DIR"
    systemctl daemon-reload
    echo "Arquivos e atalho do avell-kbd-backlight removidos."
    echo "O pacote acpi-call-dkms foi preservado porque pode ser usado por outros programas."
}

if [ "$ACTION" = uninstall ]; then
    uninstall_project
    exit 0
fi

"$SCRIPT_DIR/avell-kbd-backlight" detect

KERNEL_HEADERS="linux-headers-$(uname -r)"
PACKAGES="acpi-call-dkms dkms policykit-1 python3 libglib2.0-bin libnotify-bin x11-utils $KERNEL_HEADERS"
MISSING_PACKAGES=
for package in $PACKAGES; do
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
        MISSING_PACKAGES="$MISSING_PACKAGES $package"
    fi
done

if [ -n "$MISSING_PACKAGES" ]; then
    echo "Instalando dependencias:$MISSING_PACKAGES"
    apt-get update
    apt-get install -y $MISSING_PACKAGES
else
    echo "Todas as dependencias ja estao instaladas."
fi

if ! modinfo acpi_call >/dev/null 2>&1; then
    echo "O pacote foi instalado, mas o modulo acpi_call nao foi gerado." >&2
    echo "Verifique: dkms status e journalctl -u dkms" >&2
    exit 1
fi

if ! modprobe acpi_call; then
    echo "Nao foi possivel carregar acpi_call." >&2
    echo "Se o Secure Boot estiver ativo, o modulo DKMS pode precisar ser assinado." >&2
    exit 1
fi

if [ "$HARDWARE_TEST" -eq 1 ]; then
    if [ -f "$STATE_DIR/state.json" ]; then
        echo "Testando sem alterar o nivel salvo..."
        "$SCRIPT_DIR/avell-kbd-backlight" restore
    else
        echo "Testando a retroiluminacao no nivel 1..."
        "$SCRIPT_DIR/avell-kbd-backlight" brightness 1
    fi
else
    echo "Teste do hardware ignorado por solicitacao."
fi

install -o root -g root -m 0755 "$SCRIPT_DIR/avell-kbd-backlight" "$PROGRAM"

cat > "$WRAPPER" <<EOF
#!/bin/sh
level=\$(pkexec "$PROGRAM" --print-level cycle) || exit \$?

case "\$level" in
    0)
        label="Desligada"
        percent=0
        ;;
    1)
        label="Brilho medio"
        percent=50
        ;;
    2)
        label="Brilho maximo"
        percent=100
        ;;
    *)
        echo "Nivel inesperado retornado pelo controlador: \$level" >&2
        exit 1
        ;;
esac

printf '%s\n' "\$label"

show_notification() {
    notify-send \\
        --app-name="Avell Keyboard Backlight" \\
        --icon=keyboard-brightness-symbolic \\
        --urgency=low \\
        --expire-time=1500 \\
        --hint=string:x-canonical-private-synchronous:avell-kbd-backlight \\
        --hint=int:value:"\$percent" \\
        --hint=boolean:transient:true \\
        "Retroiluminacao do teclado" "\$1" \\
        >/dev/null 2>&1 || true
}

# Cada alteracao do brilho continua imediata. Somente a notificacao espera um
# curto periodo; uma nova entrada invalida os avisos anteriores, de modo que
# apenas o estado final de uma sequencia rapida aparece na tela.
if command -v notify-send >/dev/null 2>&1; then
    runtime_dir=\${XDG_RUNTIME_DIR:-}
    if [ -n "\$runtime_dir" ] && [ -d "\$runtime_dir" ] && [ -w "\$runtime_dir" ]; then
        notify_state="\$runtime_dir/avell-kbd-backlight-notify"
        token="\$\$-\$(date +%s)"
        temporary=\$(mktemp "\$runtime_dir/.avell-kbd-notify.XXXXXX") || exit 0
        umask 077
        printf '%s\n' "\$token" > "\$temporary"
        mv -f "\$temporary" "\$notify_state"

        (
            sleep 0.7
            current_token=\$(sed -n '1p' "\$notify_state" 2>/dev/null) || exit 0
            [ "\$current_token" = "\$token" ] || exit 0
            show_notification "\$label"
        ) >/dev/null 2>&1 &
    else
        show_notification "\$label"
    fi
fi
EOF
chmod 0755 "$WRAPPER"

printf '%s\n' acpi_call > "$MODULE_CONF"
chmod 0644 "$MODULE_CONF"

cat > "$POLICY" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
  "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
  "http://www.freedesktop.org/standards/PolicyKit/1.0/policyconfig.dtd">
<policyconfig>
  <vendor>Local Avell B.ON keyboard backlight controller</vendor>
  <action id="io.github.avell-kbd-backlight.control">
    <description>Controlar a retroiluminacao do teclado Avell</description>
    <message>Autenticacao necessaria para controlar a retroiluminacao</message>
    <defaults>
      <allow_any>no</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>yes</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">$PROGRAM</annotate>
    <annotate key="org.freedesktop.policykit.exec.allow_gui">false</annotate>
  </action>
</policyconfig>
EOF
chmod 0644 "$POLICY"

cat > "$SERVICE" <<EOF
[Unit]
Description=Restaurar a retroiluminacao do teclado Avell B.ON
Wants=systemd-modules-load.service
After=systemd-modules-load.service
ConditionPathExists=$PROGRAM

[Service]
Type=oneshot
ExecStartPre=/sbin/modprobe acpi_call
ExecStart=$PROGRAM restore --retries 3 --delay 1

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$SERVICE"

cat > "$SLEEP_HOOK" <<EOF
#!/bin/sh
if [ "\${1:-}" = post ]; then
    # O EC/WMI pode levar alguns instantes para voltar a aceitar comandos.
    sleep 1
    if "$PROGRAM" restore --retries 3 --delay 1; then
        logger -t avell-kbd-backlight "Retroiluminacao restaurada apos \${2:-suspensao}."
    else
        status=\$?
        logger -t avell-kbd-backlight "Falha ao restaurar apos \${2:-suspensao} (status \$status)."
        exit "\$status"
    fi
fi
EOF
chmod 0755 "$SLEEP_HOOK"

systemctl daemon-reload
systemctl enable --now avell-kbd-backlight-restore.service

if [ "$INSTALL_SHORTCUT" -eq 1 ]; then
    if ! configure_cinnamon_shortcut install; then
        echo "Aviso: nao foi possivel criar o atalho automaticamente no Cinnamon." >&2
        echo "Crie-o manualmente para o comando: $WRAPPER" >&2
    fi
fi

echo
echo "Instalacao concluida."
echo "Controlador: $PROGRAM"
echo "Comando de ciclo: $WRAPPER"
echo "Atalho padrao do Cinnamon: $SHORTCUT"
echo "Teste manual: $WRAPPER"
echo "Teste do resume: sudo $PROGRAM restore --retries 3 --delay 1"
echo "Remocao: sudo $SCRIPT_DIR/install.sh --uninstall"
echo
echo "Para usar especificamente Fn + tecla com icone, essa combinacao precisa aparecer no xev."
echo "Se nao aparecer, o firmware exige um driver de eventos WMI, como clevo_wmi."
