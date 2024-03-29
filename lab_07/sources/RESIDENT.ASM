;для начала нужно сохранить модифицируемые регистры (все)
;проинициализировать сегментные регистры
;выполнение необходимых действий
;восстановление используемых регистров

;структура резидентной программы:
;1. данные и подпрограммы обработчиков прерываний
;2. секция инициализация (имеет точку входа init)
;в неё передается управление при запуске программы
;секция инициализации устанавливает резидентную программу
;в память, потом её удаляет
;секция инициализации располагается в старших разрядах
;("обрезать" можем только старшие адреса)

;используем файл с расширением .com для оставления min памяти 
;.model tiny сегменты кода, данных и стека объединены.
;Эта модель предназначена для создания файлов типа СОМ.
.model tiny
.186 ;для pusha, popa

.data
	install_speed_msg db "Speed is installed.", 13, 10, '$'
	uninstall_speed_msg db "Speed is uninstalled.", 13, 10, '$'
.code
org 100h
main:
	;выделение указателя под произвольный адрес (4 байта)
	;копируем адрес предыдущего обработчика
	old_handler:
		jmp start_speed_timer ; 2 байта 
		dw ?  ; 2 байта
		current_time db 0
	speed db 00111111b  ; начальная скорость 11111 = 2.0cимв/сек
						; 01 - пауза перед началом автоповтора 500ms
	;маркер для запуска/окончания резидентной программы
	install_marker db 'S'

change_speed:
	;нужно сначала сохранить все регистры в стеке
	pusha ;сохраняет все РОН
	pushf ;сохраняет регистр флагов
	push ds ;сгружаем сегментные регистры
	push es
	
	;доступ к часам BIOS; необходимо для изменения скорости за одну секунду
	;02H ¦AT¦ читать время из "постоянных" (CMOS) часов реального времени
    ;выход: CH = часы в коде BCD   (пример: CX = 1243H = 12:43)
           ;CL = минуты в коде BCD
           ;DH = секунды в коде BCD
    ;выход: CF = 1, если часы не работают
	mov ah, 02h
	;чтение времени из rtc
	int 1ah
	
	;проверка на измение времени
	cmp dh, current_time
	mov current_time, dh
	je quit
	
	;прерывание int 60h - регистр управления клавиатурой
	;байт, записанный в этот порт интерпретируется как команда
	;некоторые команды состоят из более чем одного байта
	;(следует дождаться обнуления этоого бита перед тем,
	;как посылать следующие сигналы)
	;команда 0F3h - установить параметры режима автоповтора
	mov al, 0F3h
	;инструкция OUT выводит данные из регистра AL или AX 
	;(ИСТОЧНИК) в порт ввода-вывода
	out 60h, al
	mov al, speed
	out 60h, al
	
	dec speed
	;test = and, только без сохранения результата
	test speed, 00001111b ;проверка на 0000 1111
	;если все биты равны нулю
	jz repeat_handler
	jmp quit
	repeat_handler:
		mov speed, 00001111b
	
	;выход из программы
	quit:
		;необходимо выгрузить все сохраненные регистры обратно из стека
		pop es ;выгружаем сегментные регистры
		pop ds
		popf ;выгружаем регистр флагов
		popa ;выгружает РОН
		
		jmp dword ptr cs:old_handler
	
	
start_speed_timer:
	;используем int 21h для размещения резидентной программы
	;(так как именно там можем вектор изменить на адрес одной
	;из своих процедур (особенности таблицы векторов прерывания int XX)
	;где XX - номер прерывания от 0 до 255
	;(старший байт)DOS (35h) - получить адрес обработчика прерывания
	mov ax, 351Ch
	int 21h
	
	;проверка, установлена ли скорость или нет
	cmp es:install_marker, 'S'
	je stop_speed_timer
	
	;установить старый обработчик
	;установка смещения старого обработчика
	mov word ptr old_handler, bx
	;установка сегмента обработчика
	mov word ptr old_handler + 2, es
	
	;вывод сообщения об установке скорости
	mov dx, offset install_speed_msg
	mov ah, 09h
	int 21h
	
	;DOS (25h) - установить адрес обработчика прерывания	
	mov ax, 251Ch
	mov dx, offset change_speed
	int 21h
	
	
	;завершение программ с оставлением в памяти для com-программ.
	;для этого в dx должно находиться количество байтов, которые
	;следует оставить от начала PSP.
	;(смещение команды, начиная с которой фрагмент программы может
	;быть удален из памяти)
	mov dx, offset start_speed_timer
	int 27h
	
stop_speed_timer:
	mov ah, 09h
	mov dx, offset uninstall_speed_msg
	int 21h
	
	;восстановление смещения обработчика
	mov dx, word ptr es:old_handler
	;восстановление сегмента обработчика
	mov ds, word ptr es:old_handler + 2
	
	;установить адрес нашего обработчика
	;используем прерывание 1ch, которое регулярно получает управление
	;а не перепрограммирует таймер
	mov ax, 251Ch
	int 21h
	
	;освободить память 
	mov ah, 49h
    int 21h
	
	;может сам освобождать память
	mov ax, 4c00h
	int 21h

END main