;*******************************
;	Boot1.asm
;		- The primay bootloader
;		- Kavyansh Gangwar
;	Rudra Operating System
;*******************************

org 0x7c00	; Set loading address to fixed address 0x7c00

bits 16 	; We are still in 16 bit real mode

Start:
	cli		; Clear all Interrupts
	hlt		; halt the system

times 510 - ($-$$) db 0 	;We have to be 512 bytes
dw 0xAA55	; Boot signature