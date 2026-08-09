# ERT roundtrip technical test

Консольный техтест ядра OLE/ERT **без UI**.

Сборка: открыть `ErtRoundtripTest.dpr` в Delphi IDE и Run.

Проверяет:

1. создание минимального `.ert` с `MD Programm text` + side-stream `SideMeta`;
2. запись **более длинного** модуля → повторное чтение;
3. запись **более короткого** модуля → нет хвоста старого текста;
4. SHA/size прочих OLE-потоков не изменились.
