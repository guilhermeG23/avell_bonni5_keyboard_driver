# Retroiluminação do teclado do Avell B.ON no Linux Mint

O processo completo de identificação, com comandos e interpretação dos resultados, está em
[MANUAL_DETECCAO_HARDWARE.md](./MANUAL_DETECCAO_HARDWARE.md).

## Resultado da detecção

Esta máquina foi identificada em 16/10/2026 como:

| Item | Valor detectado |
|---|---|
| Notebook / placa-mãe | Avell `B.ON` |
| Barebone | CLEVO/KAPOK, subsystem PCI `1558:4150` |
| Processador | Intel Core i5-1235U (12ª geração) |
| BIOS | Insyde `1.07.06TBN`, 29/03/2023 |
| Sistema | Linux Mint 22.3 (`zena`, base Ubuntu 24.04) |
| Kernel | `7.0.0-31-generic` |
| Teclado | `AT Translated Set 2 keyboard` (PS/2/i8042) |
| Interface do firmware | ACPI `CLV0001`/`CLV0002` e WMI `ABBC0F6D-8EA1-11D1-00A0-C90629100000` |
| Secure Boot | desativado |

O teclado não é um dispositivo RGB USB. Não existe `ITE Device(8291)` no USB e, por isso, o projeto
`avell-unofficial-control-center` não é apropriado para este modelo. A iluminação é controlada pelo
Embedded Controller (EC) por uma chamada ACPI/WMI da CLEVO. Atualmente nenhum driver está vinculado
aos dispositivos `CLV0001`/`CLV0002`, e o kernel não criou um LED `kbd_backlight` em `/sys/class/leds`.

## Solução recomendada para este equipamento

O utilitário [avell-kbd-backlight](./avell-kbd-backlight) usa somente a chamada conhecida da CLEVO
para teclados de cor fixa (`WMBB`: comando `0x27` para escrever e `0x3D` para ler o brilho). Esses são
os mesmos comandos definidos pelo driver CLEVO/TUXEDO. Ele não escreve diretamente em registradores
do EC, não tenta controlar ventoinhas e se recusa a atuar quando os IDs esperados não estão presentes.

Primeiro, apenas confirme a detecção (não requer root e não altera nada):

```bash
./avell-kbd-backlight detect
./avell-kbd-backlight --dry-run brightness 1
```

## Instalação automática

Execute apenas:

```bash
sudo ./install.sh
```

O instalador:

1. Confirma que os IDs ACPI/WMI CLEVO pertencem ao equipamento esperado.
2. Instala pelo APT `acpi-call-dkms`, DKMS, headers do kernel, Polkit, Python, GSettings e `xev`.
3. Compila e carrega o módulo `acpi_call`.
4. Faz um teste controlado no nível 1 na primeira instalação; reinstalações preservam o nível salvo.
5. Instala o controlador em `/usr/local/sbin/avell-kbd-backlight`.
6. Instala o comando simples `/usr/local/bin/avell-kbd-cycle`.
7. Configura o carregamento do módulo no boot.
8. Restaura o último nível depois do boot e depois de suspender/hibernar.
9. Cria no Cinnamon o atalho padrão **Super+F6** para circular entre desligado, médio e máximo.
10. Mostra uma notificação OSD com ícone, descrição e percentual do novo nível.

Na retomada, o firmware pode demorar um pouco para voltar a aceitar comandos. Por isso o gancho espera
um segundo e repete a restauração três vezes. O serviço de boot também faz três tentativas. Falhas não
são mais descartadas silenciosamente e podem ser consultadas com:

```bash
journalctl -b -t avell-kbd-backlight
journalctl -b -u avell-kbd-backlight-restore.service
```

O instalador deve ser executado com `sudo` a partir da sessão gráfica do usuário para conseguir gravar
o atalho no perfil correto do Cinnamon.

Para escolher outro atalho:

```bash
sudo ./install.sh --shortcut '<Primary><Alt>k'
```

Para instalar sem criar um atalho ou sem executar o primeiro teste físico:

```bash
sudo ./install.sh --no-shortcut
sudo ./install.sh --no-hardware-test
```

## Uso depois da instalação

Os níveis aceitos são `0` (desligado), `1` (médio) e `2` (máximo):

```bash
pkexec /usr/local/sbin/avell-kbd-backlight brightness 0
pkexec /usr/local/sbin/avell-kbd-backlight brightness 1
pkexec /usr/local/sbin/avell-kbd-backlight brightness 2
```

Outros comandos:

```bash
avell-kbd-cycle
pkexec /usr/local/sbin/avell-kbd-backlight toggle
pkexec /usr/local/sbin/avell-kbd-backlight on
pkexec /usr/local/sbin/avell-kbd-backlight off
```

`cycle` percorre `0 → 1 → 2 → 0`. `toggle` apenas alterna entre desligado e o último nível ligado.
Os dois comandos usam o estado persistido pelo próprio controlador. Isso evita fazer a leitura ACPI
`0x3D` imediatamente antes da escrita `0x27`, uma sequência que pode ser ignorada por alguns firmwares.

Ao usar `avell-kbd-cycle`, também é exibido um indicador visual com `0%`, `50%` ou `100%`. Ele usa o
padrão `org.freedesktop.Notifications` por meio de `notify-send`, compatível com Cinnamon, GNOME, KDE,
XFCE, MATE e a maioria dos demais ambientes gráficos. A aparência exata depende do ambiente. Se não
houver servidor de notificações, o brilho ainda será alterado normalmente.

O brilho muda imediatamente a cada acionamento, mas o indicador visual usa um intervalo de 700 ms.
Uma nova entrada dentro desse período invalida o aviso anterior. Assim, uma sequência rápida de cinco
acionamentos altera o hardware cinco vezes, porém mostra apenas uma notificação com o estado final.
As operações do controlador são serializadas por um lock para que entradas simultâneas não percam
nenhuma etapa do ciclo.

## Uso da combinação original Fn + tecla com ícone

O instalador cria **Super+F6** porque esse atalho funciona independentemente do comportamento da tecla
`Fn`. Para verificar a combinação original, execute:

```bash
xev -event keyboard
```

Deixe a janela do `xev` em foco e pressione `Fn` junto da tecla com o ícone. Se aparecer um evento
`KeyPress`, abra **Configurações do Sistema → Teclado → Atalhos personalizados**, edite o atalho
“Avell - alternar iluminação do teclado” e pressione a combinação original.

Se nada aparecer, o firmware consumiu o evento antes de ele chegar ao Cinnamon. Nesse caso, o script
sozinho não consegue capturar a tecla: seria necessário instalar `tuxedo-drivers`, cujo módulo
`clevo_wmi` recebe os eventos WMI da CLEVO. O controle continuará acessível por Super+F6.

Neste equipamento, essa é a situação observada: `acpi_call` está carregado, mas não existem os módulos
`clevo_wmi`, `clevo_acpi` ou `tuxedo_keyboard`, nem um LED `kbd_backlight` em `/sys/class/leds`.
O `acpi_call` somente envia o comando que altera a luz; ele não escuta o evento WMI produzido pela
tecla física. Portanto, **Super+F6 funciona com esta solução, mas Fn + ícone depende de um driver
CLEVO/TUXEDO adicional**. Não é recomendável instalar esse conjunto automaticamente sem antes testar
sua compatibilidade, pois ele também controla outras funções da plataforma e pode disputar o mesmo
firmware com este utilitário.

## Diagnóstico de boot e retomada

Depois de reinstalar esta versão, confirme o serviço:

```bash
systemctl status avell-kbd-backlight-restore.service
cat /var/lib/avell-kbd-backlight/state.json
```

O campo `current` deve conter o nível que será restaurado (`0`, `1` ou `2`). Para testar a mesma ação
usada no boot e na retomada sem suspender a máquina:

```bash
sudo /usr/local/sbin/avell-kbd-backlight restore --retries 3 --delay 1
```

Para remover tudo instalado por este projeto:

```bash
sudo ./install.sh --uninstall
```

O pacote `acpi-call-dkms` não é removido automaticamente, pois pode estar sendo usado por outro
programa. Para removê-lo também: `sudo apt remove acpi-call-dkms`.

## Compatibilidade com o kernel 7.0

O pacote disponível nos repositórios do Mint/Ubuntu é o `acpi-call-dkms 1.2.2-2.1`. Por ser DKMS, ele
precisa compilar novamente para cada kernel. O código desse pacote foi baixado sem ser instalado e
compilado com sucesso contra os headers exatos do kernel `7.0.0-31-generic` desta máquina. Depois da
instalação, confirme o resultado local com:

```bash
dkms status
modinfo acpi_call
```

Se uma atualização futura do kernel quebrar a compilação, não force escritas em
`/sys/kernel/debug/ec/ec0/io`. As alternativas são, nesta ordem:

1. Inicializar temporariamente pelo kernel anterior do Mint em **GRUB → Opções avançadas** e testar
   `acpi-call-dkms` nele.
2. Testar a versão atual do pacote oficial `tuxedo-drivers` (módulos `tuxedo_keyboard`, `clevo_acpi`
   e `clevo_wmi`). A versão 4.25.0 já contém ajustes para kernels atuais, mas é um conjunto muito maior
   de drivers e deve ser compilado/testado antes de ser instalado.
3. Enviar à Avell os IDs ACPI `CLV0001`/`CLV0002`, o GUID WMI acima e pedir suporte Linux ou a
   documentação do comando de retroiluminação do Control Center.

O driver `uniwill-laptop` que já acompanha este kernel não corresponde ao equipamento: ele exige IDs
DMI de plataformas Uniwill compatíveis, enquanto esta máquina apresenta a interface ACPI CLEVO.

## Segurança e recuperação

- Comece pelo nível 1 e teste `off`/`on`; não automatize antes disso.
- Salve o trabalho antes do primeiro teste. A interface ACPI do fabricante não é documentada
  publicamente para este SKU específico.
- Se uma chamada causar comportamento anormal, desligue completamente o notebook, desconecte a fonte
  por alguns segundos e ligue novamente. Não repita a chamada.
- O utilitário não altera BIOS/UEFI nem grava firmware. A remoção dos arquivos instalados é feita por
  `sudo ./install.sh --uninstall`.

## Referências

- [TUXEDO Drivers (driver Linux para plataformas CLEVO)](https://gitlab.com/tuxedocomputers/development/packages/tuxedo-drivers)
- [Documentação e engenharia reversa da chamada WMBB](https://github.com/gtozzi/clevo-backlight)
- [Código do driver CLEVO/TUXEDO e eventos das teclas Fn](https://github.com/tuxedocomputers/tuxedo-keyboard/blob/master/src/clevo_keyboard.h)
- [Relato específico do B.ON Lite sem ITE 8291](https://github.com/rodgomesc/avell-unofficial-control-center/issues/72)

