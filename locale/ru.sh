# shellcheck shell=bash
# Russian UI for glasser. glasser sources this file when the UI language
# is Russian (GLASSER_LANG=ru or a ru_* locale).
#
# _l10n_ru KEY  — sets T to the translation of the English KEY (the key
#                 itself stays in T when there is no translation);
# _plural_ru    — Russian noun form for a count (see _plural in glasser);
# _help_ru      — --help text.
#
# Keys are the exact English strings from glasser, printf formats
# included: keep every %s / %d in the same order. run-tests.sh checks
# that every key in glasser is here and that nothing here is stale.

# shellcheck disable=SC2034  # T is read by glasser
_l10n_ru() {
    case "$1" in
        '%s: section [%s] has no key %s')
            T='%s: в [%s] нет ключа %s' ;;
        'lens database not found: %s (template: lenses.example.ini next to the script)')
            T='не найдена база объективов: %s (шаблон — lenses.example.ini рядом со скриптом)' ;;
        '%s: empty id in []')
            T='%s: пустой id в []' ;;
        '%s: whitespace in id [%s]')
            T='%s: пробел в id [%s]' ;;
        '%s: id [%s] already defined above')
            T='%s: id [%s] уже есть выше' ;;
        '%s: key before the first [id] section')
            T='%s: ключ до первой секции [id]' ;;
        '%s: unknown key "%s" in [%s]')
            T='%s: неизвестный ключ '\''%s'\'' в [%s]' ;;
        '%s: key %s repeated in [%s]')
            T='%s: ключ %s в [%s] повторяется' ;;
        '%s: expected [id] or "key = value": %s')
            T='%s: ожидается [id] или «ключ = значение»: %s' ;;
        'lens database has no entries: %s')
            T='в базе объективов нет ни одной записи: %s' ;;
        'add_camera %s: unknown MakerNote group "%s" (expected Nikon|FujiFilm|"")')
            T='add_camera %s: неизвестная MakerNote-группа '\''%s'\'' (ожидается Nikon|FujiFilm|"")' ;;
        'error: %s\n')
            T='ошибка: %s\n' ;;
        '\n%s%s◉%s %sGroup %d%s %sof %d · %d %s%s\n')
            T='\n%s%s◉%s %sГруппа %d%s %sиз %d · %d %s%s\n' ;;
        '\n[Group %d/%d]  %d %s\n')
            T='\n[Группа %d/%d]  %d %s\n' ;;
        '(no lens EXIF)')
            T='(нет EXIF объектива)' ;;
        'Scanning: ')
            T='Сканирую: ' ;;
        'Files')
            T='Файлов' ;;
        'Camera')
            T='Камера' ;;
        'Status')
            T='Статус' ;;
        'tagged')
            T='прошито' ;;
        'failed')
            T='ошибка' ;;
        'skipped')
            T='пропущено' ;;
        'skip')
            T='пропустить' ;;
        '#')
            T='№' ;;
        'Lens')
            T='Объектив' ;;
        'mm')
            T='мм' ;;
        'Make')
            T='Производитель' ;;
        'Model')
            T='Модель' ;;
        'Focal')
            T='Фокус' ;;
        'Gen.')
            T='Покол.' ;;
        'Serial')
            T='Серийник' ;;
        'Crop')
            T='Кроп' ;;
        '\nTo be written:\n')
            T='\nБудет записано:\n' ;;
        '  LensSerialNumber  = (none — the old one is cleared)\n')
            T='  LensSerialNumber  = (нет — старый стирается)\n' ;;
        '  FocalLength       = %s mm\n')
            T='  FocalLength       = %s мм\n' ;;
        '  35mm equivalent   = %s mm (×%s)\n')
            T='  Эквивалент 35мм   = %s мм (×%s)\n' ;;
        '  MakerNote (%s) = focal length + aperture + Lens="%s"\n')
            T='  MakerNote (%s) = фокусное + диафрагма + Lens="%s"\n' ;;
        '  MakerNote (%s) = focal length + aperture\n')
            T='  MakerNote (%s) = фокусное + диафрагма\n' ;;
        'Camera:')
            T='Камера:' ;;
        'Lens:')
            T='Объектив:' ;;
        'detected')
            T='угадано' ;;
        'not detected')
            T='не угадана' ;;
        'guessed')
            T='угадан' ;;
        'ambiguous:')
            T='неоднозначно:' ;;
        'not guessed')
            T='не угадан' ;;
        'input closed (EOF, Ctrl-D)')
            T='ввод закрыт (EOF, Ctrl-D)' ;;
        'no terminal')
            T='нет терминала' ;;
        'terminal lost — nothing written (use --no-confirm)')
            T='терминал пропал — ничего не записано (используй --no-confirm)' ;;
        '%s — nothing written')
            T='%s — ничего не записано' ;;
        'Number [%s]: ')
            T='Номер [%s]: ' ;;
        '\n%s and no guessed value — cancelled\n')
            T='\n%s и нет угаданного значения — отмена\n' ;;
        '(hint: --camera ID / --lens ID for scripted runs)\n')
            T='(подсказка: --camera ID / --lens ID для скриптового режима)\n' ;;
        'no guessed value, enter a number\n')
            T='нет угаданного значения, нужно явно ввести номер\n' ;;
        'invalid input, enter 0..%d\n')
            T='неверный ввод, введите 0..%d\n' ;;
        'Choose a camera (Enter keeps the detected one):')
            T='Выберите камеру (Enter — оставить угаданную):' ;;
        'Choose a camera:')
            T='Выберите камеру:' ;;
        'Choose a lens (Enter keeps the guessed one):')
            T='Выберите объектив (Enter — оставить угаданный):' ;;
        'Choose a lens (ambiguous: %s):')
            T='Выберите объектив (неоднозначно: %s):' ;;
        'Choose a lens:')
            T='Выберите объектив:' ;;
        '\n%sAccept?   %sY%s accept   %sn%s change   %ss%s skip   %sq%s quit\n\n')
            T='\n%sПринять выбор?   %sY%s принять   %sn%s исправить   %ss%s пропустить   %sq%s выйти\n\n' ;;
        '\nAccept?\n\n')
            T='\nПринять выбор?\n\n' ;;
        '  [Y] accept         [q] quit\n')
            T='  [Y] принять        [q] выйти\n' ;;
        '  [n] change         [s] skip group\n\n')
            T='  [n] исправить      [s] пропустить группу\n\n' ;;
        '%senter Y / n / q / s\n')
            T='%sвведите Y / n / q / s\n' ;;
        'enter Y / n\n')
            T='введите Y / n\n' ;;
        'unknown MakerNote group: %s')
            T='неизвестная MakerNote-группа: %s' ;;
        '%s%s Scanning…')
            T='%s%s Сканирую…' ;;
        'scanning…')
            T='сканирую…' ;;
        'EXIF for manual lenses')
            T='EXIF для мануальных объективов' ;;
        '--camera requires an ID')
            T='--camera требует ID' ;;
        '--lens requires an ID')
            T='--lens требует ID' ;;
        'extra argument: %s')
            T='лишний аргумент: %s' ;;
        'unknown option: %s')
            T='неизвестная опция: %s' ;;
        'camera not in the database: %s')
            T='камера не найдена в базе: %s' ;;
        'lens not in the database: %s')
            T='объектив не найден в базе: %s' ;;
        'not a folder: %s')
            T='не папка: %s' ;;
        'exiftool not found in PATH')
            T='не найден exiftool в PATH' ;;
        'no terminal — use --no-confirm')
            T='нет терминала — используй --no-confirm' ;;
        'no images in the folder: %s')
            T='в папке нет изображений: %s' ;;
        'path with a newline: %s')
            T='путь с переводом строки: %s' ;;
        'path is not absolute: %s')
            T='путь не абсолютный: %s' ;;
        'no readable images in the folder: %d %s skipped — control characters (newline, TAB) in a file or folder name, or exiftool could not read the file: %s')
            T='в папке нет читаемых изображений: пропущено %d %s — управляющие символы (перевод строки, TAB) в имени файла или папки, либо exiftool не смог прочитать файл: %s' ;;
        'Analyzing: %s\n')
            T='Анализирую: %s\n' ;;
        'Files: %d\n')
            T='Всего файлов: %d\n' ;;
        'Files: %d, groups: %d\n\n')
            T='Всего файлов: %d, групп: %d\n\n' ;;
        'warning: %d %s skipped — control characters (newline, TAB) in a file or folder name, or exiftool could not read the file\n')
            T='внимание: пропущено %d %s — управляющие символы (перевод строки, TAB) в имени файла или папки, либо exiftool не смог прочитать файл\n' ;;
        '\nCancelled. Nothing written.\n')
            T='\nОтмена. Ничего не записано.\n' ;;
        'group %d/%d: camera not detected (need --camera ID)')
            T='группа %d/%d: не угадал камеру (нужен --camera ID)' ;;
        'group %d/%d: lens is ambiguous: %s — need --lens ID')
            T='группа %d/%d: объектив неоднозначен: %s — нужен --lens ID' ;;
        'group %d/%d: lens not guessed (need --lens ID)')
            T='группа %d/%d: не угадал объектив (нужен --lens ID)' ;;
        'Skip group')
            T='Пропустить группу' ;;
        'Back')
            T='Назад' ;;
        'Group %d/%d: ')
            T='Группа %d/%d: ' ;;
        '\nNothing to apply: all groups skipped.\n')
            T='\nНечего применять: все группы пропущены.\n' ;;
        'Apply the plan?')
            T='Применить план?' ;;
        'exiftool failed in groups: %s; the other groups were processed')
            T='exiftool завершился с ошибкой в группах: %s; остальные группы обработаны' ;;
        '\n━━━ Write plan ━━━\n')
            T='\n━━━ План записи ━━━\n' ;;
        '\nWarning details:\n')
            T='\nПодробности warning'\''ов:\n' ;;
        '  %s: no structural warnings in the file\n')
            T='  %s: структурных warning'\''ов в файле нет\n' ;;
        '    (exiftool warned while writing; the file was updated.\n')
            T='    (warning от exiftool при записи; файл обновлён.\n' ;;
        '    Details: `exiftool -v "%s" 2>&1 | grep -B 3 -i warning`)\n')
            T='    Подробнее: `exiftool -v "%s" 2>&1 | grep -B 3 -i warning`)\n' ;;
        'interrupted (Ctrl-C) before group %d: it and the following ones are untouched')
            T='прервано (Ctrl-C) перед группой %d: она и следующие не тронуты' ;;
        '\n# Group %d/%d (%s + %s):\n')
            T='\n# Группа %d/%d (%s + %s):\n' ;;
        '\n--- dry-run, the command is not executed: ---\n')
            T='\n--- dry-run, команда не выполняется: ---\n' ;;
        '\nRunning exiftool for group %d/%d...\n')
            T='\nЗапускаю exiftool для группы %d/%d...\n' ;;
        '\nRunning exiftool...\n')
            T='\nЗапускаю exiftool...\n' ;;
        'interrupted (Ctrl-C) in group %d: it may be partly written, the following ones are untouched')
            T='прервано (Ctrl-C) на группе %d: она могла записаться частично, следующие не тронуты' ;;
        'exiftool failed (group %d)')
            T='exiftool завершился с ошибкой (группа %d)' ;;
        '✓ Done.\n')
            T='✓ Готово.\n' ;;
        '\n✗ Done with errors.\n')
            T='\n✗ Готово с ошибками.\n' ;;
        '\nTotal: %d %s tagged')
            T='\nИтого: прошито %d %s' ;;
        ', %d %s failed (some may be partly written)')
            T=', с ошибкой %d %s (часть могла записаться)' ;;
        ', %d %s skipped')
            T=', пропущено %d %s' ;;
        'Tagged:')
            T='Прошито:' ;;
        'Failed:')
            T='С ошибкой:' ;;
        '  %s %d %s (some may be partly written)\n')
            T='  %s %d %s (часть могла записаться)\n' ;;
    esac
}

# Russian plural: $1 — the count, $2 / $3 — English singular / plural.
_plural_ru() {
    local one few many last=$(($1 % 10)) last_two=$(($1 % 100))
    case "$2" in
        file)  one=файл   few=файла  many=файлов ;;
        group) one=группа few=группы many=групп ;;
        *)     printf '%s' "$3"; return 0 ;;
    esac
    if (( last_two >= 11 && last_two <= 14 )); then
        printf '%s' "$many"
    elif (( last == 1 )); then
        printf '%s' "$one"
    elif (( last >= 2 && last <= 4 )); then
        printf '%s' "$few"
    else
        printf '%s' "$many"
    fi
}

_help_ru() {
    cat <<'EOF'
glasser — прошивка EXIF/XMP/MakerNote-тегов для мануальной оптики через адаптеры.

Использование:
  glasser                       обработать текущую папку (с подпапками)
  glasser PATH                  обработать указанную папку (с подпапками)
  glasser --list-lenses         таблица объективов
  glasser --list-cameras        таблица камер
  glasser --dry-run [PATH]      показать команду, не записывать
  glasser --no-confirm [PATH]   без интерактива (по угаданному)
  glasser --camera ID [PATH]    принудительно эта камера
  glasser --lens   ID [PATH]    принудительно этот объектив
  glasser --verbose [PATH]      сериальный прогресс вместо прогресс-бара
  glasser --no-art [PATH]       без заставки, спиннера и анимации
  glasser --version             версия
  glasser --help                эта справка

Обрабатываются jpg, jpeg, nef, raf, tif, tiff, dng, arw, cr2, cr3.
--camera / --lens действуют на все группы папки.

База объективов — файл lenses.ini рядом со скриптом: секция [id]
на объектив, формат описан в шапке файла. База камер встроена
в скрипт — функция load_camera_db.

Язык: английский, при русской локали — русский; GLASSER_LANG=en|ru
задаёт явно.
EOF
}
