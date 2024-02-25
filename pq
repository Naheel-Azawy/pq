#!/bin/sh

# platformio quick

toolchain=
init_at=
speed=
devs=
dev=
env=
tty_only=
build_only=

SPEEDS='115200
9600
300
600
1200
2400
4800
14400
19200
38400
57600
230400
460800'

G='\033[1m\033[32m' # green
Y='\033[1m\033[33m' # yellow
B='\033[1m\033[34m' # blue
C='\033[1m\033[36m' # cyan
E='\033[1m\033[31m' # red
R='\033[0m'         # reset

export MENUCONFIG_STYLE='aquatic list=fg:white,bg:black' # for idf.py

info() {
    printf "${B}INFO:${R} %s\n" "$@"
}

ask() {
    printf "${Y}QUESTION:${R} %s\n" "$@"
}

ans() {
    printf "${C}ANSWER:${R} %s\n" "$@"
}

err() {
    printf "${E}ERROR:${R} %s\n" "$@" >&2
}

exists() {
    command -v "$1" >/dev/null
}

menu() {
    items=$(echo "$1" | sed 's/\\n/\n/g' | grep .)
    shift
    if exists fzf; then
        height=$(echo "$items" | wc -l)
        height=$((height + 2))
        echo "$items" | fzf --height "$height" "$@"
    else
        numbered=$(echo "$items" | nl)
        echo "$numbered" >/dev/tty
        read -r ans </dev/tty
        echo "$numbered" | sed -rn "s/^\s*$ans\s\s*(.+)/\1/p"
    fi
}

ask_menu() {
    q="$1"
    i="$2"
    shift 2
    ask "$q" >/dev/tty
    a=$(menu "$i" "$@")
    if [ -n "$a" ]; then
        ans "$a" >/dev/tty
        echo "$a"
    else
        ans "Skipped" >/dev/tty
        return 1
    fi
}

show_cmd() {
    printf "${G}\$${R} %s\n" "$*"
}

run() {
    show_cmd "$@"
    "$@"
}

run_ask() {
    show_cmd "$@"
    c=$(ask_menu 'Run the command above?' 'Yes\nNo')
    if [ "$c" = Yes ]; then
        "$@"
    else
        return 1
    fi
}

usage() {
    bin=$(basename "$0")
    echo "usage $bin [OPTION]..."
    echo '  -r ARGS    execute raw command'
    echo '  -i PATH    init a new project'
    echo '  -p DEV     port'
    echo '  -s SPEED   baud rate'
    echo '  -e ENV     pio environment'
    echo '  -t         tty only'
    echo '  -b         build only'
    echo '  -h         show this help'
}

parse_args() {
    while getopts ':i:p:s:e:tbh' arg; do
        case ${arg} in
            i) init_at="${OPTARG}"  ;;
            t) tty_only=1           ;;
            b) build_only=1         ;;
            p) dev="${OPTARG}"      ;;
            s) speed="${OPTARG}"    ;;
            e) env="${OPTARG}"      ;;
            *) usage; return 1      ;;
        esac
    done
}

# shellcheck disable=SC1091
prepare_pio() {
    if ! exists pio; then
        pio_path="$HOME/.local/share/platformio"
        if ! [ -d "$pio_path" ]; then
            info 'Installing platformio...'
            (mkdir -p "$pio_path"                   &&
                 cd "$pio_path"                     &&
                 python3 -m virtualenv pio-env      &&
                 . "$pio_path/pio-env/bin/activate" &&
                 pip install platformio
            )
        fi
        if ! [ -d "$pio_path" ]; then
            err 'No platformio installation found'
        else
            . "$pio_path/pio-env/bin/activate"
        fi
    fi
    pio_bin=$(which pio)
    info "Using pio: $pio_bin"
}

# shellcheck disable=SC1091
prepare_apio() {
    if ! exists apio; then
        apio_path="$HOME/.local/share/apio"
        if ! [ -d "$apio_path" ]; then
            info 'Installing apio...'
            (mkdir -p "$apio_path"                   &&
                 cd "$apio_path"                     &&
                 python3 -m virtualenv pio-env      &&
                 . "$apio_path/pio-env/bin/activate" &&
                 pip install apio
            )
        fi
        if ! [ -d "$apio_path" ]; then
            err 'No apio installation found'
        else
            . "$apio_path/pio-env/bin/activate"
        fi
    fi
    apio_bin=$(which apio)
    info "Using apio: $apio_bin"
}

# shellcheck disable=SC1090
prepare_idf() {
    if [ -z "$IDF_PATH" ]; then
        IDF_PATH="$HOME/.local/share/esp/esp-idf"
        esp_idf_exports="$IDF_PATH/export.sh"
        if [ -f "$esp_idf_exports" ]; then
            # . "$esp_idf_exports"
            # the above is too slow, but safe
            # but since this script will re-do this on every run, let's take the risk

            export IDF_PATH
            # Call idf_tools.py to export tool paths
            export IDF_TOOLS_EXPORT_CMD="${IDF_PATH}/export.sh"
            export IDF_TOOLS_INSTALL_CMD="${IDF_PATH}/install.sh"
            # Allow calling some IDF python tools without specifying the full path
            # ${IDF_PATH}/tools is already added by 'idf_tools.py export'
            IDF_ADD_PATHS_EXTRAS="${IDF_PATH}/components/espcoredump"
            IDF_ADD_PATHS_EXTRAS="${IDF_ADD_PATHS_EXTRAS}:${IDF_PATH}/components/partition_table"
            IDF_ADD_PATHS_EXTRAS="${IDF_ADD_PATHS_EXTRAS}:${IDF_PATH}/components/app_update"

            idf_exports=$(python3 "${IDF_PATH}/tools/idf_tools.py" export "--add_paths_extras=${IDF_ADD_PATHS_EXTRAS}") || return 1
            eval "${idf_exports}"
            export PATH="${IDF_ADD_PATHS_EXTRAS}:${PATH}"
        else
            mkdir -p "$HOME/.local/share/esp" &&
                cd "$HOME/.local/share/esp" &&
                git clone --recursive https://github.com/espressif/esp-idf.git &&
                cd esp-idf &&
                ./install.fish esp32
        fi
    fi

    idf_bin=$(which idf.py)
    info "Using idf.py: $idf_bin"
}

prepare() {
    case "$toolchain" in
        apio) prepare_apio ;;
        idf)  prepare_idf  ;;
        *)    prepare_pio  ;;
    esac
}

init() {
    # TODO: init for other toolchains

    path=${1-.}
    mkdir -p "$path/src"

    {
        echo '[env:esp32dev]'
        echo 'platform = espressif32'
        echo 'board = esp32dev'
        echo 'framework = arduino'
        echo
        echo '[env:nodemcuv2]'
        echo 'platform = espressif8266'
        echo 'board = nodemcuv2'
        echo 'framework = arduino'
        echo
        echo '[env:uno]'
        echo 'platform = atmelavr'
        echo 'board = uno'
        echo 'framework = arduino'

    } >"$path/platformio.ini"

    {
        echo '#include <Arduino.h>'
        echo
        echo '#define LED 2 // LED_BUILTIN'
        echo
        echo 'void setup() {'
        echo '    pinMode(LED, OUTPUT);'
        echo '}'
        echo
        echo 'void loop() {'
        echo '    digitalWrite(LED, HIGH);'
        echo '    delay(500);'
        echo '    digitalWrite(LED, LOW);'
        echo '    delay(500);'
        echo '}'
    } > "$path/src/main.cpp"
}

start_serial() {
    run pio device monitor -p "$dev" -b "$speed" --raw
}

set_dev() {
    if [ -n "$dev" ]; then
        if ! echo "$devs" | grep -q "$dev"; then
            err "Device '$dev' is not found"
            return 1
        fi
    else
        devs_len=$(echo "$devs" | wc -l)
        if [ -n "$devs" ] && [ "$devs_len" -gt 1 ]; then
            dev=$(ask_menu 'Select device' "$devs")
            [ -n "$dev" ] || return 1
        else
            dev="$devs"
        fi
    fi
}

set_env() {
    if [ -z "$env" ] && [ -f ./platformio.ini ]; then
        envs=$(sed -rn 's/\[env:(.+)\]/\1/p' ./platformio.ini)
        envs_len=$(echo "$envs" | wc -l)
        if [ -n "$envs" ] && [ "$envs_len" -gt 1 ]; then
            env=$(ask_menu 'Select build environment:' "$envs")
            [ -n "$env" ] || return 1
        else
            env="$envs"
        fi
    fi
}

set_speed() {
    if [ "$speed" = s ] || [ -z "$speed" ]; then
        # check platform.ini file
        if [ -f ./platformio.ini ]; then
            ini_speed=$(sed -rn 's/monitor_speed *= *(.+)/\1/p' ./platformio.ini |
                     head -n1)
            if echo "$SPEEDS" | grep -q "$ini_speed"; then
                # is a valid baud rate
                speed="$ini_speed"
                [ -n "$speed" ] &&
                    info "Setting speed to $speed from ./platformio.ini"
            fi
        fi

        # check source file(s)
        if [ -z "$speed" ] && [ -d ./src ]; then
            src_speed=$(cd ./src && grep -r 'Serial\.begin('           |
                                sed -rn 's/.*Serial\.begin\((.+)\).*/\1/p' |
                                uniq)
            # be sure there is only one speed
            src_speeds_count=$(echo "$src_speed" | wc -l)
            if [ "$src_speeds_count" = 1 ] &&
                   echo "$SPEEDS" | grep -q "$src_speed"; then
                speed="$src_speed"
                [ -n "$speed" ] &&
                    info "Setting speed to $speed from source file(s)"
            fi
        fi
    fi

    if [ -z "$speed" ]; then
        # don't know what to do; ask user
        speed=$(ask_menu 'Select serial tty baud rate:' "$SPEEDS")
        [ -n "$speed" ] || return 1
    fi
}

set_toolchain() {
    if [ -f ./platformio.ini ]; then
        toolchain=pio
    elif [ -f ./apio.ini ]; then
        toolchain=apio
    elif [ -f ./sdkconfig ] && grep -q ESP-IDF ./sdkconfig; then
        toolchain=idf
    else
        toolchain=pio
    fi
}

cwd_buildable() {
    [ -f ./platformio.ini ] ||
        [ -f ./apio.ini ] ||
        { [ -f ./sdkconfig ] && grep -q ESP-IDF ./sdkconfig; }
}

build() {
    case "$toolchain" in
        pio)
            set_env && run pio run -e "$env" ;;
        apio)
            run apio build ;;
        idf)
            run idf.py build ;;
    esac
}

upload() {
    case "$toolchain" in
        pio)
            set_env && set_dev && set_speed &&
                run_ask pio run -t upload -e "$env" --upload-port "$dev" &&
                start_serial ;;
        apio)
            run apio build && run apio upload ;;
        idf)
            run idf.py build upload monitor ;;
    esac
}

monitor() {
    case "$toolchain" in
        pio|apio)
            set_dev && set_speed && start_serial ;;
        idf)
            run idf.py monitor ;;
    esac
}

main() {
    set_toolchain

    if [ "$1" = '-r' ]; then
        shift
        cmd="$1"
        case "$cmd" in
            pio)        prepare_pio             ;;
            apio)       prepare_apio            ;;
            idf.py)     prepare_idf             ;;
            idf)        prepare_idf; cmd=idf.py ;;
            *)
                err "unknown command '$1'"
                return 1
        esac
        shift
        exec "$cmd" "$@"
    fi

    prepare || return
    parse_args "$@" || return

    # possible options
    options='New project\n'
    cwd_buildable && options="${options}Build\n"
    devs=$(find /dev/ -maxdepth 1 -name 'ttyACM*' -or -name 'ttyUSB*' |
               sort -nr)
    if [ -n "$devs" ]; then
        [ -n "$devs" ] && options="${options}Serial monitor\n"
        cwd_buildable && [ -n "$devs" ] && options="${options}Upload\n"
    fi

    # args option, if any
    if [ -n "$init_at" ]; then
        option='New project'
    elif [ -n "$tty_only" ]; then
        option='Serial monitor'
    elif [ -n "$build_only" ]; then
        option='Build'
    else
        option=
    fi

    # check options
    if [ -n "$option" ]; then
        if ! echo "$options" | grep -q "$option"; then
            err "$option is currently not possible"
            return 1
        fi
    else
        option=$(ask_menu 'What to do?' "$options" --tac)
    fi

    # run
    case "$option" in
        'New project')
            if [ -z "$init_at" ]; then
                ask 'Select project path:'
                read -r init_at
            fi
            [ -n "$init_at" ] || {
                err "Path can't be empty"
                return 1
            }
            init "$init_at" ;;

        'Build')          build   ;;
        'Upload')         upload  ;;
        'Serial monitor') monitor ;;

        '')
            return 1 ;;

        *)
            err "Unknown option '$option'"
            return 1
    esac
}

main "$@"
