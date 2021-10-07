;*******************************
;	Boot1.asm
;		- The primay bootloader
;		- Kavyansh Gangwar
;	Rudra Operating System
;*******************************

org 0x7c00	; Set loading address to fixed address 0x7c00

bits 16 	; We are still in 16 bit real mode

start:	jmp loader 	; jump to loader

;*************************************************;
;	OEM Parameter block
;*************************************************;

; Error Fix 2 - Removing the ugly TIMES directive -------------------------------------

;;	TIMES 0Bh-$+start DB 0					; The OEM Parameter Block is exactally 3 bytes
								; from where we are loaded at. This fills in those
								; 3 bytes, along with 8 more. Why?

bpbOEM			db "RudraOS "				; This member must be exactally 8 bytes. It is just
								; the name of your OS :) Everything else remains the same.

bpbBytesPerSector:  	DW 512
bpbSectorsPerCluster: 	DB 1
bpbReservedSectors: 	DW 1
bpbNumberOfFATs: 	    DB 2
bpbRootEntries: 	    DW 224
bpbTotalSectors: 	    DW 2880
bpbMedia: 	            DB 0xF0
bpbSectorsPerFAT: 	    DW 9
bpbSectorsPerTrack: 	DW 18
bpbHeadsPerCylinder: 	DW 2
bpbHiddenSectors: 	    DD 0
bpbTotalSectorsBig:     DD 0
bsDriveNumber: 	        DB 0
bsUnused: 	            DB 0
bsExtBootSignature: 	DB 0x29
bsSerialNumber:	        DD 0xa0a1a2a3
bsVolumeLabel: 	        DB "MOS FLOPPY "
bsFileSystem: 	        DB "FAT12   "

msg db "Welcome to RudraOS!", 0

;************************************
;	Prints a string
;	DS=>SI: 0 terminated string
;************************************

Print:
	lodsb
	or 	al, al
	jz  PrintDone
	mov ah, 0eh
	int 10h
	jmp Print
PrintDone:
	ret

;************************************
;	Bootloader entry Point
;************************************

loader:
	xor ax, ax
	mov ds, ax
	mov es, ax
	mov si, msg
	call Print
	xor ax, ax
	int 0x12
	cli		; Clear all Interrupts
	hlt		; halt the system

times 510 - ($-$$) db 0 	;We have to be 512 bytes
dw 0xAA55	; Boot signature

