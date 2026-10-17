# Manual de detecção do hardware do Avell B.ON

Este documento registra como o notebook, a placa-mãe, o teclado e a interface de controle da
retroiluminação foram identificados. Os comandos de diagnóstico desta página são somente de leitura e
podem ser repetidos sem instalar drivers ou alterar o firmware.

Data do levantamento: **16/10/2026**.

## 1. Resultado resumido

| Componente | Resultado |
|---|---|
| Fabricante e produto | Avell `B.ON` |
| Plataforma física | CLEVO/KAPOK, subsystem PCI `1558:4150` |
| CPU | Intel Core i5-1235U, 12ª geração |
| BIOS | Insyde `1.07.06TBN`, de 29/03/2023 |
| Teclado interno | PS/2, apresentado como `AT Translated Set 2 keyboard` |
| Tipo de iluminação | Cor fixa/single-color, controlada pelo firmware/EC |
| Ponte ACPI CLEVO | `CLV0001` (`DCHU`) e `CLV0002` (`DCHP`) |
| Método WMI CLEVO | GUID `ABBC0F6D-8EA1-11D1-00A0-C90629100000`, objeto `BB` |
| Interface LED do Linux | Não criada; nenhum `kbd_backlight` em `/sys/class/leds` |
| Controlador USB ITE 8291 | Não encontrado |

A conclusão é que a retroiluminação não faz parte do dispositivo PS/2 que envia as teclas. Ela é uma
função separada do Embedded Controller (EC), acessível pela interface ACPI/WMI da CLEVO.

## 2. Identificação DMI do notebook e da placa-mãe

O kernel publica os dados SMBIOS/DMI em `/sys/class/dmi/id`. Esses arquivos normalmente podem ser
lidos sem `sudo`:

```bash
for campo in \
    sys_vendor product_name product_version \
    board_vendor board_name board_version \
    bios_vendor bios_version bios_date
do
    printf '%s: ' "$campo"
    cat "/sys/class/dmi/id/$campo" 2>/dev/null
done
```

Resultado relevante desta máquina:

```text
sys_vendor: Avell
product_name: B.ON
board_vendor: Avell
board_name: B.ON
bios_vendor: INSYDE Corp.
bios_version: 1.07.06TBN
bios_date: 03/29/2023
```

A Avell substituiu no DMI o nome original do barebone pelo nome comercial `B.ON`. Portanto, apenas
esses campos não revelam o código de fábrica da CLEVO; foi necessário conferir os dispositivos PCI e
ACPI.

Para exibir o alias DMI completo:

```bash
cat /sys/class/dmi/id/modalias
```

Neste notebook ele contém, entre outros valores, `svnAvell`, `pnB.ON` e BIOS `1.07.06TBN`.

## 3. Sistema operacional, kernel e CPU

```bash
cat /etc/os-release
uname -a
lscpu | grep -E 'Vendor ID|Model name'
```

Foi detectado:

```text
Linux Mint 22.3 (Zena), base Ubuntu Noble
Kernel 7.0.0-31-generic x86_64
Intel Core i5-1235U
```

O kernel é importante porque drivers externos compilados com DKMS precisam ser compatíveis com a
versão em execução.

## 4. Confirmação do fabricante real pelo barramento PCI

Execute:

```bash
lspci -nnk
```

Vários componentes integrados apresentaram o mesmo subsystem:

```text
Subsystem: CLEVO/KAPOK Computer Device [1558:4150]
```

O fabricante PCI `1558` pertence à CLEVO/KAPOK. A repetição de `1558:4150` no host bridge, vídeo,
controladores USB, áudio, rede e outros componentes confirma que a placa é uma plataforma CLEVO
revendida pela Avell.

Para obter somente as linhas relevantes:

```bash
lspci -nnk | grep -B1 -A2 '1558:4150'
```

## 5. Identificação do teclado que envia as teclas

Os dispositivos de entrada podem ser enumerados assim:

```bash
cat /proc/bus/input/devices
```

O teclado interno apareceu como:

```text
N: Name="AT Translated Set 2 keyboard"
P: Phys=isa0060/serio0/input0
H: Handlers=sysrq kbd event4 leds
```

Isso identifica um teclado interno ligado à interface PS/2/i8042. A palavra `leds` nessa saída se
refere aos indicadores tradicionais do protocolo de teclado, como Caps Lock e Num Lock; ela não prova
a existência de controle para a iluminação sob as teclas.

Para observar se uma combinação `Fn` chega à sessão gráfica X11:

```bash
xev
```

Deixe a janela do `xev` em foco e pressione a combinação. Um evento `KeyPress` significa que o atalho
pode ser associado diretamente pelo Cinnamon. Se nada aparecer, o firmware consumiu a combinação e
será necessário um driver que receba o evento WMI, como `clevo_wmi`, ou outro atalho personalizado.

## 6. Verificação dos dispositivos USB

O objetivo desta etapa foi verificar se existia um controlador de iluminação USB separado:

```bash
lsusb
```

Também é possível ler os IDs diretamente pelo sysfs:

```bash
for dispositivo in /sys/bus/usb/devices/*; do
    [ -r "$dispositivo/idVendor" ] || continue
    printf '%s:%s  ' \
        "$(cat "$dispositivo/idVendor")" \
        "$(cat "$dispositivo/idProduct")"
    cat "$dispositivo/product" 2>/dev/null || true
done
```

Foram encontrados áudio USB, câmera e o controlador Bluetooth Intel. Não apareceu o dispositivo
`Integrated Technology Express ITE Device(8291)`. Por isso, ferramentas criadas especificamente para
o ITE 8291, como o antigo `avell-unofficial-control-center`, não são compatíveis com este B.ON.

## 7. Descoberta da interface ACPI CLEVO

Para procurar dispositivos ACPI específicos do fabricante:

```bash
find /sys/bus/acpi/devices -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
```

Neste equipamento aparecem:

```text
CLV0001:00
CLV0002:00
```

Os detalhes foram lidos com:

```bash
for dispositivo in CLV0001:00 CLV0002:00; do
    base="/sys/bus/acpi/devices/$dispositivo"
    printf '\n%s\n' "$dispositivo"
    printf 'HID: '; cat "$base/hid"
    printf 'UID: '; cat "$base/uid"
    printf 'Caminho: '; cat "$base/path"
    printf 'Status: '; cat "$base/status"
    printf 'Driver: '; readlink "$base/driver" 2>/dev/null || echo nenhum
done
```

Resultado:

```text
CLV0001:00 -> caminho ACPI \_SB_.DCHU, sem driver
CLV0002:00 -> caminho ACPI \_SB_.DCHP, sem driver
```

`CLV0001` é a ponte ACPI utilizada pelos drivers CLEVO para conversar com o firmware. A ausência de
um link em `driver` mostra que nenhum módulo Linux estava controlando essa interface durante o
levantamento.

## 8. Descoberta do método WMI

Os GUIDs WMI disponíveis foram listados com:

```bash
find /sys/bus/wmi/devices -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
```

Resultado:

```text
ABBC0F6B-8EA1-11D1-00A0-C90629100000
ABBC0F6C-8EA1-11D1-00A0-C90629100000
ABBC0F6D-8EA1-11D1-00A0-C90629100000
```

O GUID terminado em `6D` é a interface de métodos CLEVO. A confirmação do objeto WMI `BB` pode ser
feita assim:

```bash
base=/sys/bus/wmi/devices/ABBC0F6D-8EA1-11D1-00A0-C90629100000
cat "$base/guid"
cat "$base/object_id"
cat "$base/instance_count"
```

Resultado:

```text
ABBC0F6D-8EA1-11D1-00A0-C90629100000
BB
1
```

Esse objeto corresponde ao método ACPI `WMBB`, usado pelo driver CLEVO para executar comandos do EC.

## 9. Verificação da interface de LEDs do Linux

```bash
find /sys/class/leds -maxdepth 2 -type f \
    \( -name brightness -o -name max_brightness \) \
    -print -exec cat {} \;
```

Nenhum dispositivo com nome `kbd_backlight` foi retornado. Isso explica por que programas como
`brightnessctl` não conseguem controlar o teclado: sem um driver CLEVO, o kernel não registra essa
iluminação no subsistema padrão de LEDs.

Uma verificação curta pode ser feita com:

```bash
find /sys/class/leds -maxdepth 1 -printf '%f\n' | grep -i kbd
```

## 10. Módulos do kernel examinados

```bash
lsmod | grep -Ei 'clevo|tuxedo|uniwill|wmi|acpi|hid'
find "/lib/modules/$(uname -r)" -type f \
    | grep -Ei '/(clevo|tuxedo|uniwill).*\.ko'
```

Não havia `clevo_acpi`, `clevo_wmi` ou `tuxedo_keyboard` carregado. O kernel contém o módulo
`uniwill-laptop`, mas os aliases DMI dele não correspondem a `Avell B.ON`, e a interface encontrada é
CLEVO (`CLV0001`), não Uniwill.

## 11. Secure Boot e requisitos para módulos externos

```bash
mokutil --sb-state
test -e "/lib/modules/$(uname -r)/build/Makefile" \
    && echo "headers presentes" \
    || echo "headers ausentes"
```

Foi encontrado:

```text
SecureBoot disabled
headers presentes
```

Isso simplifica o teste de módulos DKMS, pois não será necessário assinar manualmente o módulo para o
Secure Boot. O pacote `acpi-call-dkms 1.2.2-2.1` também foi extraído e compilado, sem instalação, contra
os headers `7.0.0-31-generic`; a compilação produziu um módulo com o `vermagic` correto.

## 12. Como as evidências levaram ao diagnóstico

| Evidência | Interpretação |
|---|---|
| DMI informa Avell B.ON | Identifica o produto comercial |
| PCI subsystem `1558:4150` | Confirma a plataforma CLEVO/KAPOK |
| Teclado `AT Translated Set 2` | As teclas são transmitidas pela interface PS/2 |
| ITE 8291 ausente no USB | Descarta o driver USB usado por outros modelos Avell |
| ACPI `CLV0001`/`CLV0002` | Confirma a ponte de controle CLEVO/Insyde |
| WMI `ABBC0F6D...`, objeto `BB` | Confirma a interface do método `WMBB` |
| Nenhum `kbd_backlight` no sysfs | Mostra que falta um driver para expor a iluminação ao Linux |
| Especificação single-color | Direciona para os comandos CLEVO de brilho fixo `0x27`/`0x3D` |

## 13. Coleta rápida para outro notebook

O bloco abaixo reúne somente informações de leitura. Ele pode ser copiado para um terminal e o
resultado salvo manualmente, se necessário:

```bash
echo '=== SISTEMA ==='
cat /etc/os-release
uname -a

echo '=== DMI ==='
for campo in sys_vendor product_name product_version board_vendor board_name bios_vendor bios_version bios_date; do
    printf '%s: ' "$campo"
    cat "/sys/class/dmi/id/$campo" 2>/dev/null || true
done

echo '=== CPU ==='
lscpu | grep -E 'Vendor ID|Model name'

echo '=== PCI CLEVO ==='
lspci -nnk | grep -B1 -A2 '1558:' || true

echo '=== TECLADOS ==='
grep -A5 -B1 -i keyboard /proc/bus/input/devices || true

echo '=== USB ==='
lsusb || true

echo '=== ACPI CLEVO ==='
find /sys/bus/acpi/devices -mindepth 1 -maxdepth 1 -printf '%f\n' \
    | grep -Ei 'CLV|ITE' || true

echo '=== WMI ==='
find /sys/bus/wmi/devices -mindepth 1 -maxdepth 1 -printf '%f\n' | sort

echo '=== LEDS ==='
find /sys/class/leds -maxdepth 1 -printf '%f\n' 2>/dev/null | sort

echo '=== MODULOS ==='
lsmod | grep -Ei 'clevo|tuxedo|uniwill|wmi|acpi|hid' || true

echo '=== SECURE BOOT ==='
mokutil --sb-state 2>&1 || true
```

Antes de publicar essa saída na internet, revise números de série, UUIDs, endereços MAC e outros
identificadores pessoais. Os comandos deste manual não solicitam esses dados, mas ferramentas mais
amplas como `dmidecode`, `inxi -Fxxx` e `hw-probe` podem incluí-los.

## 14. Comandos opcionais que exigem root

Uma inspeção mais profunda pode usar:

```bash
sudo dmidecode -t system -t baseboard -t bios
sudo acpidump -n DSDT -b -o dsdt.dat
iasl -d dsdt.dat
```

Esses comandos são de leitura, mas o arquivo DSDT decompilado é grande e só é necessário para
engenharia reversa ou confirmação detalhada do método `WMBB`. Eles não são necessários para usar o
controlador criado neste diretório.

Não escreva valores diretamente em `/sys/kernel/debug/ec/ec0/io`. O EC também controla energia,
bateria e ventoinhas; um endereço incorreto pode travar o equipamento.

## 15. Diagnóstico após a primeira instalação

Depois da instalação, foi confirmado que `acpi_call` estava carregado, mas continuavam ausentes
`clevo_wmi`, `clevo_acpi`, `tuxedo_keyboard` e o LED `kbd_backlight`. Isso separa as duas funções:

- `acpi_call` consegue enviar o comando `WMBB 0x27` e, por isso, acende e apaga o teclado;
- sem `clevo_wmi`, ninguém recebe do firmware o evento da combinação física `Fn + ícone`.

O atalho **Super+F6** criado no Cinnamon chama o controlador diretamente e não depende desse evento.
Usar especificamente a combinação original requer um driver CLEVO/TUXEDO compatível com a máquina;
não é uma limitação que possa ser corrigida apenas mudando o atalho do script.

Também foi encontrado um problema independente na restauração. O gancho antigo executava uma única
chamada logo no início do `post` e descartava tanto a saída quanto o erro. O EC pode ainda não estar
pronto nesse instante. A versão atual espera um segundo, faz três escritas idempotentes e registra o
resultado no journal. O serviço de boot passou a aguardar `systemd-modules-load.service`, em vez de
declarar uma ordenação circular com o próprio `multi-user.target`.

Nos testes do atalho, os registros do Polkit confirmaram que o Cinnamon executava o comando, embora a
mudança não fosse aplicada de forma confiável. O comando `cycle` fazia uma leitura `WMBB 0x3D` seguida
imediatamente da escrita `WMBB 0x27`. Ele foi alterado para usar o estado persistido, evitando duas
chamadas consecutivas ao firmware e garantindo a sequência `0 → 1 → 2 → 0`.

O wrapper do atalho também usa `notify-send` para publicar o novo nível por meio da interface
`org.freedesktop.Notifications`. Essa interface é independente do Cinnamon e funciona nos principais
ambientes gráficos. O servidor pode exibir uma barra de `0%`, `50%` ou `100%`; quando não oferece esse
recurso, ainda mostra o ícone e a descrição textual do nível.

Para evitar uma fila de avisos durante vários acionamentos rápidos, a notificação tem debounce de
700 ms: cada nova entrada substitui o token da anterior e somente o último processo publica o aviso.
A mudança física continua imediata. Um lock em `/run/lock/avell-kbd-backlight.lock` também serializa
os comandos, garantindo que cada acionamento avance exatamente um nível mesmo sob concorrência.

Comandos de verificação depois de reinstalar:

```bash
systemctl status avell-kbd-backlight-restore.service
journalctl -b -u avell-kbd-backlight-restore.service
journalctl -b -t avell-kbd-backlight
cat /var/lib/avell-kbd-backlight/state.json
```

## 16. Próxima etapa

O procedimento de instalação e teste do controlador está no [README.md](./README.md). Antes de fazer
qualquer alteração, a detecção também pode ser repetida pelo utilitário local:

```bash
./avell-kbd-backlight detect
./avell-kbd-backlight --dry-run brightness 1
```

