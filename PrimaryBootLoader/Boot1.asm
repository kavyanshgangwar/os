;********************************************************************
;		Boot1.asm
;		- Kavyansh Gangwar
;			This is the first stage bootloader which loads the
;			Second stage bootloader
;********************************************************************

;********************************************************************
;		basic structure
;********************************************************************

bits	16							; We are in 16 bit real mode
org		0							; We will set registers later
start:	jmp		main				; jump to start of the bootloader

;********************************************************************
;		BIOS PARAMETER BLOCK
;********************************************************************

;	BPB begins 3 bytes from start.

bpbOEM						db		"Rudra OS"			;OEM identifier (8 bytes)
bpbBytesPerSector:			DW		512
bpbSectorPerCluster:		DB		1
bpbReservedSectors:			DW		1
bpbNumberOfFATs:			DB		2
bpbRootEntries:				DW		224
bpbTotalSectors:			DW		2880
bpbMedia:					DW		0xf8
bpbSectorsPerFAT:			DW		9
bpbSectorsPerTrack:			DW		18
bpbHeadsPerCylinder:		DW		2
bpbHiddenSectors:			DD		0
bpbTotalSectorsBig:			DD		0
bsDriveNumber:				DB		0
bsUnused:					DB		0
bsExtBootSignature:			DB		0x29
bsSerialNumber:				DD		0xa0a1a2a3
bsVolumeLabel:				DB		"MOS FLOPPY "
bsFileSystem:				DB		"FAT12   "


;********************************************************************
;		Prints a String
;		DS=>SI: 0 terminated string
;********************************************************************
Print:
							lodsb						; load next byte from string from SI to AL
							or		al,	al				; check if AL=0?
							jz		PrintDone			; if AL is zero then end the function
							mov		ah, 0eh				; Print the character
							int		10h
							jmp		Print
		PrintDone:
							ret							; return 
							
;********************************************************************
;		Reads a series of sectors 
;		CX => Number of sectors to read
;		AX => Starting Sector
;		ES:BX => Buffer to read to
;********************************************************************

ReadSectors:
	.MAIN
		mov		di,		0x0005							; five retries for error
	.SECTORLOOP
		push	ax
		push	bx
		push	cx
		call	LBACHS									; convert LBA to CHS
		mov		ah,		0x02							; BIOS read sector
		mov		al,		0x01							; read 1 sector
		mov		ch,		BYTE	[absoluteTrack]			; track
		mov		cl,		BYTE	[absoluteSector]		; sector
		mov		dh,		BYTE	[absoluteHead]			; head
		mov		dl,		BYTE	[bsDriveNumber]			; boot sector drive
		int		0x13									; invoke BIOS
		jnc		.SUCCESS								; if successful then move to .SUCCESS
		xor		ax,		ax								; BIOS reset disk
		int		0x13
		dec		di										; decrement error counter
		pop		cx
		pop		bx
		pop		ax
		jnz		.SECTORLOOP								; attempt to read again
		int		0x18
	.SUCCESS
		mov		si,		msgProgress
		call	Print
		pop		cx
		pop		bx
		pop		ax
		add		bx,		WORD	[bpbBytesPerSector]		; queue the next buffer
		inc		ax										; queue the next sector
		loop	.MAIN									; read next sector
		ret

		
;********************************************************************
;		Convert CHS to LBA
;		LBA = (cluster-2) * sectors per cluster
;********************************************************************
ClusterLBA:
		sub		ax,		0x0002							; zero base cluster number
		xor		cx,		cx
		mov		cl,		BYTE	[bpbSectorsPerCluster]	; convert byte to word
		mul		cx
		add		ax,		WORD	[datasector]			; base data sector
		ret

;********************************************************************
;		Convert LBA to CHS
;		AX => LBA address to convert
;
;		absolute sector = (logical sector / sectors per track) + 1
;		absolute head = (logical sector / sectors per tract) MOD number of heads
;		absolute track = logical sector / (sectors per track * number of heads)
;********************************************************************

LBACHS:
		xor		dx,		dx								; prepare dx:ax for operation
		div		WORD	[bpbSectorsPerTrack]			; calculate
		inc		dl										; adjust for sector 0
		mov		BYTE	[absoluteSector],		dl		
		xor		dx,		dx
		div		WORD	[bpbHeadsPerCylinder]
		mov		BYTE	[absoluteHead],			dl
		mov		BYTE	[absoluteTrack],		al
		ret
		
;********************************************************************
;		Bootloader Main function
;********************************************************************
main:

	;********************************************************************
	;		the code is located at 0000:7c00
	;		adjust segment registers
	;********************************************************************

		cli
		mov		ax,		0x07c0
		mov		ds,		ax
		mov		es,		ax
		mov		fs,		ax
		mov		gs,		ax

	
	;********************************************************************
	;		Create a stack
	;********************************************************************

		mov		ax,		0x0000							; set the stack
		mov		ss,		ax
		mov		sp,		0xFFFF
		sti												; restore interrupts
		
	;********************************************************************
	;		Display a loading message
	;********************************************************************

		mov		si,		msgLoading
		call	Print

	
	;********************************************************************
	;		Load the root directory table
	;********************************************************************

	LOAD_ROOT:

	; compute the size of root directory and store in "cx"
		xor		cx,		cx
		xor		dx,		dx
		mov		ax,		0x0020							; 32 byte directory entry
		mul		WORD	[bpbRootEntries]				; total size of directory
		div		WORD	[bpbBytesPerSector]				; sectors used by directory
		xchg	ax,		cx

	; compute location of root directory and store in "ax"
		mov		al,		BYTE	[bpbNumberOfFATs]		; number of FATs
		mul		WORD	[bpbSectorsPerFAT]				; sectors used by FATs
		add		ax,		WORD	[bpbReservedSectors]	; adjust for boot sector
		mov		WORD	[datasector],	ax				; base of root directors
		add		WORD	[datasector],	cx

	; read root directory into memory (7c00:0200)
		mov		bx,		0x0200
		call	ReadSectors

	;********************************************************************
	;		find secondary boot loader
	;********************************************************************

	; browse root directory for binary image
		mov		cx,		WORD	[bpbRootEntries]		; load loop counter
		mov		di,		0x0200
	.LOOP:
		push	cx
		mov		cx,		0x000B							; eleven character name
		mov		si,		ImageName						; image name to fing
		push	di
	rep cmpsb
		pop		di
		je		LOAD_FAT
		pop		cx
		add		di,		0x0020							; queue the next directory entry
		loop	.LOOP
		jmp		FAILURE

	;********************************************************************
	;		Load FAT
	;********************************************************************
	
	; save starting cluster of boot image
		mov		si		msgCRLF
		call	Print
		mov		dx,		WORD	[di + 0x001A]
		mov		WORD	[cluster],		dx

	; compute size of FAT and store in "cx"
		xor		ax,		ax
		mov		al,		BYTE	[bpbNumberOfFATs]
		mul		WORD	[bpbSectorsPerFAT]
		mov		cx,		ax

	; compute location of FAT and store in "ax"
		mov		ax,		WORD	[bpbReservedSectors]

	; read FAT into memory (7c00:0200)
		mov		bx,		0x0200
		call	ReadSectors
	
	; read image file into memory (0050:0000)
		mov		si,		msgCRLF
		call	Print
		mov		ax,		0x0050
		mov		es,		ax
		mov		bx,		0x0000
		push	bx

	;********************************************************************
	;		Load seconday boot loader
	;********************************************************************

	LOAD_IMAGE:
		mov		ax,		WORD	[cluster]
		pop		bx
		call	ClusterLBA
		xor		cx,		cx
		mov		cl,		BYTE	[bpbSectorsPerCluster]
		call	ReadSectors
		push	bx
	
	; compute next cluster
		
		mov		ax,		WORD	[cluster]
		mov		cx,		ax
		mov		dx,		ax
		shr		dx,		0x0001
		add		cx,		dx
		mov		bx,		0x0200
		add		bx,		cx
		mov		dx,		WORD	[bx]
		test	ax,		0x0001
		jnz		.ODD_CLUSTER

	.EVEN_CLUSTER:
		and		dx,		0000111111111111b
		jmp		.DONE

	.ODD_CLUSTER:
		shr		dx,		0x0004

	.DONE:
		mov		WORD	[cluster],	dx
		cmp		dx,		0x0ff0
		jb		LOAD_IMAGE

	DONE:
		mov		si,		msgCRLF
		call	Print
		push	WORD	0x0050
		push	WORD	0x0000
		retf

	FAILURE:
		mov		si,		msgFailure
		call	Print
		mov		ah,		0x00
		int		0x16
		int		0x19

	absoluteSector		db		0x00
	absoluteHead		db		0x00
	absoluteTrack		db		0x00

	datasector			dw		0x0000
	cluster				dw		0x0000
	ImageName			db		"STAGE2  SYS"
	msgLoading			db		0x0D,	0x0A,	"Loading Boot Image",	0x0D,	0x0A,	0x00
	msgCRLF				db		0x0D,	0x0A,	0x00
	msgProgress			db		".",	0x00
	msgFailure			db		0x0D,	0x0A,	"ERROR : Press Any Key to Reboot",	0x0A,	0x00

	TIMES 510 -($-$$)	DB		0
	DW					0xAA55