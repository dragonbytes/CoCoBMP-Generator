
*************************************************************************************
* BMP Screenshot Generator for BASIC Programs
* Written by Todd Wallace
*************************************************************************************
* I thought other people might find it useful or interesting to capture a text screen
* from a BASIC program and save it to disk as a real BMP file screenshot.
* NOTE: It currently only works with the two Hi-Res text modes (WIDTH 40/80)
*************************************************************************************

coco3_slow 		EQU 	$FFD8
coco3_fast 		EQU 	$FFD9

gime_init0 	EQU 	$FF90 
gime_init1 	EQU 	$FF91
gime_vmode 	EQU 	$FF98
gime_vres 	EQU 	$FF99
gime_border 	EQU 	$FF9A
gime_512k_bank 	EQU 	$FF9B 		; normally reserved, switches 512k vram space for large ram upgrade. also allows more than 2 MB of ram 
gime_vert_scroll 	EQU 	$FF9C
gime_vert_offset	EQU 	$FF9D
mmu_bank0  	EQU  	$FFA0  		; Controls Task 0 $0000-$1FFF
mmu_bank1  	EQU  	$FFA1  		; Controls Task 0 $2000-$3FFF
mmu_bank2  	EQU  	$FFA2 		; Controls Task 0 $4000-$5FFF
mmu_bank3  	EQU  	$FFA3  		; Controls Task 0 $6000-$7FFF
mmu_bank4 	EQU 	$FFA4 		; Controls Task 0 $8000-$9FFF
mmu_bank5  	EQU  	$FFA5   		; Controls Task 0 $A000-$BFFF
mmu_bank6  	EQU  	$FFA6 		; Controls Task 0 $C000-$DFFF
mmu_bank7  	EQU  	$FFA7 		; Controls Task 0 $E000-$FFFF
gime_palette0 	EQU 	$FFB0
gime_palette1 	EQU 	$FFB1
gime_palette2 	EQU 	$FFB2
gime_palette3 	EQU 	$FFB3
gime_palette4 	EQU 	$FFB4
gime_palette5 	EQU 	$FFB5
gime_palette6 	EQU 	$FFB6
gime_palette7 	EQU 	$FFB7
gime_palette8 	EQU 	$FFB8
gime_palette9 	EQU 	$FFB9
gime_palette10	EQU 	$FFBA
gime_palette11 	EQU 	$FFBB
gime_palette12 	EQU 	$FFBC

	org  	$3000

hires_text_bitmap	EQU 	$F09D

; Variables
screenWidth 		RMB  	1   		; Offset 0
screenHeight 		RMB  	1   		; Offset 1
attrEnabled 		FCB  	1   		; Offset 2
scanlinesPerChar  	FCB  	8  		; Offset 3
vramBlockMMU  	FCB  	$36   		; Offset 4
bmpBufferBlockMMU 	FCB  	$31  		; Offset 5
vramScreenStartPtr  	FDB  	$6000 		; Offset 6
bmpBufferStartPtr  	FDB  	$4000 		; Offset 8
destDriveNum  	RMB  	1   		; Offset 10
statusBarColorBG  	RMB  	1   		; Offset 11
statusBarColorFG  	RMB  	1  		; Offset 12
progressBarColorBG  	RMB  	1  		; Offset 13
borderColor   	FCB  	0   		; Offset 14

vramCharPtr   	RMB  	2
vramTotalBytes  	RMB  	2
vramProgressBarPtr 	RMB  	2
vramStatusStartPtr	RMB  	2
vramStatusEndPtr  	RMB  	2
progressBarWholeStep	RMB  	1
progressBarRemSteps	RMB  	1
progressBarRemCount	RMB  	1
vramProgressTextPtr 	RMB  	2
vramOrigBlockMMU 	RMB  	1
vramGimeRegister	RMB 	2

bmpBufferCurPtr 	RMB  	2
bmpBufferEndPtr  	RMB  	2
bmpOrigBlockMMU  	RMB  	1
bmpGimeRegister	RMB  	2

charColorBackground  RMB  	1
charColorForeground 	RMB  	1

gimePalRegsImage	RMB  	16

widthCounter		RMB  	1
heightCounter		RMB  	1
bytesPerRow 		RMB  	2
doubleBytesPerRow	RMB  	2
pixelPairCounter 	RMB  	1
romCharRowCounter  	RMB  	1
borderHeightCounter	RMB  	1
bmpBorderHeight  	RMB  	1  	; Height in BMP pixels of one border (top or bottom)
pixelPairBytes  	RMB  	1

sectorBufferPtr  	RMB  	2
sectorBufferEndPtr  	RMB  	2

fileSizeAddBuffer  	RMB  	4

origStackPtr  	RMB  	2

destFilename 		FCC  	"SCRNCAPx"  	; 'x' will be replaced by the first number that is not on disk already
			FCC  	"BMP"	

strCheckingDisk  	FCN  	"  Checking disk..."
strCaptureProgress 	FCN  	"  Screenshot capture in progress..."
strCaptureDone  	FCN  	"  Screenshot saved!"
strErrorOutOfSpace	FCN  	"  Error: Ran out of disk space. Image incomplete."
strErrorFilename  	FCN  	"  Error: Could not create BMP file."

rgbGimeConvTable  	FCB 	0,85,170,255

colorPtrs  		FDB  	charColorBackground,charColorForeground

;colorTableHiNibble	FCB  	$80,$90,$A0,$B0,$C0,$D0,$E0,$F0,$00,$10,$20,$30,$40,$50,$60,$70
;colorTableLoNibble  	FCB  	$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$00,$01,$02,$03,$04,$05,$06,$07
colorTableHiNibble	FCB  	$00,$10,$20,$30,$40,$50,$60,$70,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0
colorTableLoNibble  	FCB  	$00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F
colorTableDoubled  	FCB  	$00,$11,$22,$33,$44,$55,$66,$77,$88,$99,$AA,$BB,$CC,$DD,$EE,$FF

; BITMAPFILEHEADER Definition Bytes (All values expressed as little-endian)
bitmapFileHeader 	FCC  	"BM"  			; bfType - File Signature
fileTotalSizeOffset	EQU  	*-bitmapFileHeader
			FQB  	0  			; bfSize - Total file size in bytes
			FDB  	0  			; bfReserved1 - Must be 0
			FDB  	0  			; bfReserved2 - Must be 0
			FCB  	$76,$00,$00,$00	; bfOffBits - Offset from beginning of file to start of pixel array

; BITMAPINFOHEADER Definition Bytes (All values expressed as little-endian)
bitmapInfoHeader  	FCB  	$28,$00,$00,$00   	; biSize - Header Size (40 Bytes)
			FCB 	$80,$02,$00,$00	; biWidth - Image Width (640 pixels)
			FCB  	$E0,$01,$00,$00 	; biHeight - Image Height (480 pixels. Negative values flip orientation) 
			FCB  	$01,$00  		; biPlanes - Number of bitplanes (1)
			FCB  	$04,$00  		; biBitCount - Bits per Pixel (4)  	
			FCB  	$02,$00,$00,$00  	; biCompression - Compression type (2 = BI_RLE4)
pixelDataSizeOffset	EQU  	*-bitmapFileHeader
			FQB  	0  			; biSizeImage - Pixel Data Size in Bytes
			FQB  	0  			; biXPelsPerMeter - Horizontal Pixels per Meter
			FQB  	0  			; biYPelsPerMeter - Vertical Pixels per Meter
			FCB  	$10,$00,$00,$00  	; biClrUsed - Numbers of colors defined in palette (16)
			FQB  	0  			; biClrImportant - Important color (0 = all)

bmpColorPaletteDefs	ZMB  	(16*4)  		; 4 Bytes per defintion (Blue, Green, Red, Reserved)

bitmapFileHeaderSz 	EQU  	*-bitmapFileHeader

rgbColorBlueOffset 	EQU  	0
rgbColorGreenOffset 	EQU  	1
rgbColorRedOffset 	EQU  	2

	include 	decb.asm

START
; -----------------------------------------------
; Entry: A = screen width in chars, B = screen height in chars
; 	  X = ptr to hires text vram to screenshot
;  	  Y = ptr of where to store bmp buffer data (needs at least 5760 bytes of space)
; -----------------------------------------------
SCREENSHOT_TEXT
	pshs 	U,Y,X,D,CC

	orcc 	#$50
	
	sts  	origStackPtr
	lds  	#$4000

	lda 	destDriveNum
	jsr  	DSKCON_INIT

	lda  	#4   		; Assume 80 columns to start
	ldb  	screenWidth
	cmpb  	#40
	bne  	SCREENSHOT_TEXT_NO_DOUBLE_PIXEL_WIDTH
	lda  	#8    		; 8 bytes per character for double width pixels
SCREENSHOT_TEXT_NO_DOUBLE_PIXEL_WIDTH
	sta  	pixelPairBytes
	stb  	widthCounter
	tst  	attrEnabled
	beq  	SCREENSHOT_TEXT_NO_ATTR
	lslb  	; 2 bytes per character, so multiply by 2
SCREENSHOT_TEXT_NO_ATTR
	clra
	std  	bytesPerRow
	lslb
	rola
	std   	doubleBytesPerRow

	; Calculate the height of our top/bottom border (to bring total BMP height to 480 pixels)
	lda  	scanlinesPerChar
	ldb  	screenHeight
	mul  	; B will contain total height in pixels of usable coco screen
	negb
	addb  	#240  	; 240 scales to 480 when scanlines are doubled in output to match aspect ratio
	stb  	bmpBorderHeight
	;ldb  	#15
	;stb  	bmpBorderHeight
	
	; Calculate the end ptr for our bmp file buffer
	ldd  	bmpBufferStartPtr
	std  	bmpBufferCurPtr  	; Init our bmp current buffer ptr to start 
	tfr  	D,U
	; Effectively calculates the bytes needed for one full row of rendered 4bpp pixels.
	; (Screen width in bytes * scanlines per char * 2 to correct aspect ratio)
	lda  	scanlinesPerChar
	lsla
	lsla
	ldb  	#160
	mul
	addd 	bmpBufferStartPtr
	std  	bmpBufferEndPtr

	; Calculate the end of screen memory and then position "cursor" to beginning of last row
	ldb  	bytesPerRow+1
	lda  	screenHeight
	sta  	heightCounter
	mul
	std  	vramTotalBytes
	addd  	vramScreenStartPtr
	std   	vramCharPtr
	std  	vramStatusEndPtr
	subd  	bytesPerRow
	std  	vramStatusStartPtr
	std  	vramProgressTextPtr
	std  	vramProgressBarPtr

	; Figure out how many progress-bar blocks to highlight per text row rendered/compressed/saved
	clrb
	stb  	progressBarRemSteps
	stb  	progressBarRemCount
	lda  	screenWidth
SCREENSHOT_TEXT_PROGRESS_BAR_DIVIDE_NEXT
	suba  	screenHeight
	bls 	SCREENSHOT_TEXT_PROGRESS_BAR_DIVIDE_STORE_RESULT
	incb
	bra  	SCREENSHOT_TEXT_PROGRESS_BAR_DIVIDE_NEXT

SCREENSHOT_TEXT_PROGRESS_BAR_DIVIDE_STORE_RESULT
	stb  	progressBarWholeStep
	bcc  	SCREENSHOT_TEXT_PROGRESS_BAR_DIVIDE_DONE  	; No remainder from the division
	adda  	screenHeight
	sta  	progressBarRemSteps
SCREENSHOT_TEXT_PROGRESS_BAR_DIVIDE_DONE

	; Shift FG color bits over for progress bar/message text for easier bit-merging 
	lda  	statusBarColorFG
	lsla
	lsla
	lsla
	sta  	statusBarColorFG

	; Copy current values from all GIME palette registers into an image table
	ldx  	#gime_palette0
	ldy  	#gimePalRegsImage
	ldb  	#16
SCREENSHOT_TEXT_COPY_NEXT_PALETTE
	lda  	,X+
	anda  	#%00111111 		; Mask off unused bits which will be garbage when read
	sta  	,Y+
	decb
	bne  	SCREENSHOT_TEXT_COPY_NEXT_PALETTE

	; Swap in vram to specified MMU block and address based on user settings
	ldb  	vramScreenStartPtr
	lsrb
	lsrb
	lsrb
	lsrb
	lsrb
	ldx  	#mmu_bank0
	leax  	B,X
	stx  	vramGimeRegister
	lda  	,X
	anda  	#%00111111
	sta  	vramOrigBlockMMU
	lda  	vramBlockMMU
	sta  	,X
	; Now swap in the user-specified MMU block to use a BMP buffer
	ldb  	bmpBufferStartPtr
	lsrb
	lsrb
	lsrb
	lsrb
	lsrb
	ldx  	#mmu_bank0
	leax  	B,X
	stx  	bmpGimeRegister
	lda  	,X
	anda  	#%00111111
	sta  	bmpOrigBlockMMU
	lda  	bmpBufferBlockMMU
	sta  	,X

	; Before we start doing disk access and showing statusbar messages, make a copy of bottom-most row of text
	; so it doesnt get used in the screenshot and so we can restore it later. Put it right after the end of screen vram
	ldy  	vramStatusEndPtr
	ldx  	vramStatusStartPtr
	ldb  	bytesPerRow+1
SCREENSHOT_TEXT_BUFFER_BOTTOM_TEXT_ROW_NEXT
	lda  	,X+
	sta  	,Y+
	decb
	bne  	SCREENSHOT_TEXT_BUFFER_BOTTOM_TEXT_ROW_NEXT

	ldy  	#strCheckingDisk
	jsr  	SCREENSHOT_TEXT_PRINT_MSG_ATTR

	ldy  	#decbGranMapDest
	jsr  	DECB_GET_FAT	

	ldb  	#'0'
	ldy  	#destFilename
SCREENSHOT_TEXT_FILENAME_NUM_TRY_NEXT
	stb  	7,Y
	jsr  	DECB_FIND_FILENAME
	bcs   	SCREENSHOT_TEXT_FILE_NOT_FOUND
	; If here, the current BMP screenshot filename is already used, so we have to increment the name
	incb
	cmpb   #'9'
	bls  	SCREENSHOT_TEXT_FILENAME_NUM_TRY_NEXT
	lbra  	SCREENSHOT_TEXT_ERROR_OUT_OF_NAMES

SCREENSHOT_TEXT_FILE_NOT_FOUND
	jsr  	DECB_FIND_FREE_DIR_ENTRY
	lbcs  	SCREENSHOT_TEXT_ERROR_DISK_FULL
	jsr  	DECB_FAT_FIND_EMPTY_GRANULE
	lbcs  	SCREENSHOT_TEXT_ERROR_DISK_FULL
	sta  	decbFileStartGranule
	jsr   	DECB_GET_TRACK_SECTOR_FROM_GRANULE
	incb  	; Skip over first sector containing BMP file header since it's incomplete until we finish everything
	std  	>diskTrack

	ldd  	vramStatusStartPtr
	std  	vramProgressTextPtr
	ldy  	#strCaptureProgress
	jsr  	SCREENSHOT_TEXT_PRINT_MSG_ATTR

	ldd  	#headerSectorBuffer
	std  	sectorBufferPtr
	std  	>diskDataPtr
	inca   	; Effectively adds 256 bytes to reference end of that sector buffer
	std  	sectorBufferEndPtr
	; Copy our BMP header into header disk buffer for our first sector
	ldu  	bmpBufferStartPtr
	jsr  	SCREENSHOT_TEXT_SETUP_BMP_HEADER  

	; Add bottom border
	lda  	bmpBorderHeight
	ldb  	borderColor
	jsr  	SCREENSHOT_TEXT_INSERT_RLE_BORDER_ROWS

	; Below is the main loop for capturing the screenshot and saving to disk. The process is as follows:
	; - Start at the bottom of the screen because BMP pixel data by default is bottom-up orientation
	; - Render one full row of bitmap text at a time, including extra scanlines between rows if configured to
	; - Compress the complete rendered row of text using RLE-4 compression and fill the disk sector buffer along the way
	; - When a sector is full, write it out to disk and continue adding new compressed data from where we left off
	; - When the current row of text is all rendered, compressed, and saved to disk, start the process over again
	; 	with a new row of text one line up, working our way to the top of the screen.
SCREENSHOT_TEXT_NEXT_COLUMN
	; Grab an ascii character from vram and then lookup the corresponding bitmap for it
	ldx  	vramCharPtr  		; Load vram ptr to our next character on screen
	; For attributed text modes only, decode the attribute byte for color information	
	lda  	1,X	
	ldb  	1,X
	anda  	#%00000111	
	andb  	#%00111000
	lsrb
	lsrb
	lsrb
	addb 	#8
	std  	charColorBackground

	clra
	ldb  	,X++  			; Grab the ASCII byte of next character in vram and increment/save ptr
	stx  	vramCharPtr
	subb  	#$20
	lslb
	rola
	lslb
	rola
	lslb
	rola
	addd  	#hires_text_bitmap+8   	; 4 cycles
	tfr  	D,Y  				; 6 cycles
	lda  	#8
	sta  	romCharRowCounter
SCREENSHOT_TEXT_NEXT_BITMAP_BYTE
	; Iterate through the next bitmap byte data for this character
	ldb  	,-Y
	lda  	pixelPairBytes
	sta  	pixelPairCounter
	cmpa  	#4
	beq   	SCREENSHOT_TEXT_NEXT_NIBBLE_PAIR 	; Use packed nibbles
	; For 40 column width, we have to write double-pixels for each in charater bitmap
SCREENSHOT_TEXT_NEXT_DOUBLED_PIXEL
	ldx  	#colorPtrs   		; Convienient ptr table for looking up Background/Foreground color variables
	clra   			; Zero-out our scratch A register
	lslb  				; Shift out the next highest bitmap pixel bit (0 = background pixel, 1 = foreground)
	rola  				; Rotate it into A
	lsla   			; Multiply that bit by 2 to create offset for Background/Foreground color ptr lookup
	lda  	[A,X]   		; Grab the corresponding background or foreground color value	
	ldx  	#colorTableDoubled
	lda  	A,X
	sta  	,U+  			; Store in our output buffer
	sta  	(320-1),U   		; For line-doubling to correct for aspect ratio
	dec 	pixelPairCounter
	bne  	SCREENSHOT_TEXT_NEXT_DOUBLED_PIXEL
	bra  	SCREENSHOT_TEXT_NEXT_PIXEL_CHAR_ROW

SCREENSHOT_TEXT_NEXT_NIBBLE_PAIR
	; Start with High Nibble (since our output is 4-bits per pixel)
	ldx  	#colorPtrs   		; Convienient ptr table for looking up Background/Foreground color variables
	clra   			; Zero-out our scratch A register
	lslb  				; Shift out the next highest bitmap pixel bit (0 = background pixel, 1 = foreground)
	rola  				; Rotate it into A
	lsla   			; Multiply that bit by 2 to create offset for Background/Foreground color ptr lookup
	lda  	[A,X]   		; Grab the corresponding background or foreground color value
	ldx  	#colorTableHiNibble
	lda  	A,X   			; Finally, grab the High Nibble version of our color
	sta  	,U  			; Store in our output buffer
	; Now do the Low Nibble
	ldx  	#colorPtrs   		; Convienient ptr table for looking up Background/Foreground color variables
	clra   			; Zero-out our scratch A register
	lslb  				; Shift out the next highest bitmap pixel bit (0 = background pixel, 1 = foreground)
	rola  				; Rotate it into A
	lsla   			; Multiply that bit by 2 to create offset for Background/Foreground color ptr lookup
	lda  	[A,X]   		; Grab the corresponding background or foreground color value
	ldx  	#colorTableLoNibble
	lda  	A,X   			; Finally, grab the Low Nibble version of our color
	ora  	,U  			; Merge with our High-Nibble value
	sta  	,U+  			; Store the final output byte for those 2 pixels and increment pixel data buffer ptr
	sta  	(320-1),U   		; For line-doubling to correct for aspect ratio
	dec 	pixelPairCounter
	bne  	SCREENSHOT_TEXT_NEXT_NIBBLE_PAIR
SCREENSHOT_TEXT_NEXT_PIXEL_CHAR_ROW
	; Done with one row of 8-pixel-wide output data. Move output pixel data ptr down 1 row and start of column
	ldd  	#640
	subb  	pixelPairBytes
	leau  	D,U  			; 320 bytes per row (4bpp) * 2 for aspect ratio correction
	dec  	romCharRowCounter
	bne  	SCREENSHOT_TEXT_NEXT_BITMAP_BYTE
	; If here, we finished rendering one whole character. Check if video mode is 8 or 9 scanlines per character row
	lda  	scanlinesPerChar
	cmpa  	#9
	blo  	SCREENSHOT_TEXT_NO_EXTRA_SCANLINE
	; Add an additional empty scanline for a total of 9 (doubled to correct aspect ratio)
	lda  	charColorBackground
	lsla
	lsla
	lsla
	lsla
	ora  	charColorBackground
	tfr  	A,B
	std  	,U
	std  	2,U
	std  	320,U
	std  	322,U
SCREENSHOT_TEXT_NO_EXTRA_SCANLINE		
	ldu  	bmpBufferCurPtr
	lda  	pixelPairBytes
	leau  	A,U  			; Advance BMP buffer ptr to next consecutive character in the row 
	stu  	bmpBufferCurPtr
	dec  	widthCounter
	lbne  	SCREENSHOT_TEXT_NEXT_COLUMN
	; We finished rendering one whole row of text to BMP buffer. Now write it to disk.
	jsr  	SCREENSHOT_TEXT_COMPRESS_RLE

	; Update progress bar
	jsr  	SCREENSHOT_TEXT_UPDATE_PROGRESS

	ldd  	vramCharPtr
	cmpd  	vramStatusStartPtr
	bls  	SCREENSHOT_TEXT_MOVE_UP_PREV_ROW
	; If here, we just finished rendering from our buffered copy of last row on screen. Move pointer backwards
	; PASSED the statusbar row and to the row before it to continue as normal
	ldd  	vramStatusEndPtr
SCREENSHOT_TEXT_MOVE_UP_PREV_ROW
	; Move vram ptr up to start of previous row of text
	subd  	doubleBytesPerRow
	std  	vramCharPtr
	; Reset current BMP pixel data buffer to start
	ldu  	bmpBufferStartPtr
	stu  	bmpBufferCurPtr
	; Reset text char column counter, decrement height counter and loop if more rows to render
	lda  	screenWidth
	sta  	widthCounter
	dec  	heightCounter
	lbne  	SCREENSHOT_TEXT_NEXT_COLUMN

	; Add top border 
	lda  	bmpBorderHeight
	ldb  	borderColor
	jsr  	SCREENSHOT_TEXT_INSERT_RLE_BORDER_ROWS

	; Add the final RLE4 command "End of Bitmap" ($00 $01) to very end of BMP file to mark end of our pixel data.
	; Also pad-out any remaining space in the sectorBuffer with $FF for easier debugging.
	ldx  	sectorBufferPtr
	ldd  	#$0001
SCREENSHOT_TEXT_PAD_FINAL_SECTOR_NEXT
	std  	,X++
	ldd  	#$FFFF
	cmpx  	sectorBufferEndPtr
	blo   	SCREENSHOT_TEXT_PAD_FINAL_SECTOR_NEXT

	; Write out the last remaining pixel data in our buffer to final sector on disk
	jsr  	DECB_WRITE_SECTOR
	lda  	>diskSector
	sta  	decbFileLastSectorNum 	; Needed by DECB to calculate how many sectors were used in last granule

	; The filesize counter only adds 256 bytes (one full sector) at a time when writing them to disk to save
	; cpu time, so now that we are done, we may have a partially filled sector in buffer that hasnt been added yet.
	; Use our pointers to calculate how many were leftover, add them to the count, and then store our final total
	; in the BMP header at offset "bfSize". Then subtract out size of header to get pixel data size in byte and
	; write that to BMP header as well at offset "biSizeImage".
	ldx  	#headerSectorBuffer  	
	ldd  	sectorBufferPtr
	subd  	#sectorBuffer  		; This will always be less than 256, so there wont be any carry needed 
	addd  	#2  			; when adding these 2 "End of Bitmap" bytes to the count
	std  	decbFileBytesLastSector  	; Store leftover byte count for DECB disk routine it needs for making dir entry
	addd  	fileSizeAddBuffer+2
	std  	fileSizeAddBuffer+2
	; Two seperate stores into BMP header cuz of little-endian
	stb  	fileTotalSizeOffset,X  	
	sta  	fileTotalSizeOffset+1,X
	ldb  	fileSizeAddBuffer+1
	adcb  	#0
	stb   	fileSizeAddBuffer+1
	stb  	fileTotalSizeOffset+2,X
	; Subtract header bytes and rgb color def bytes from total to get size in bytes of pixel data
	ldd  	fileSizeAddBuffer+2
	subd  	#bitmapFileHeaderSz
	stb  	pixelDataSizeOffset,X
	sta  	pixelDataSizeOffset+1,X
	ldb  	fileSizeAddBuffer+1
	sbcb  	#0
	stb  	pixelDataSizeOffset+2,X

	; Fill in whatever progress bar blocks are left 
	jsr  	SCREENSHOT_TEXT_UPDATE_PROGRESS

	; Finally, now that the BMP header is updated in our cached headerSectorBuffer, we can write it to disk
	; at the beginning of our file that we skipped over when we started
	lda  	decbFileStartGranule
	jsr  	DECB_GET_TRACK_SECTOR_FROM_GRANULE
	std  	>diskTrack
	stx  	>diskDataPtr   		; X should still have headerSectorBuffer start ptr. Set DSKCON buffer to use it
	jsr  	DSKCON_WRITE_SECTOR  	; Perform a direct sector write since we are not appending sectors anymore to file
	inc 	>diskSector  			; Because my FAT disk routines expect an auto-increment of sector after each write
	
	ldx  	#destFilename
	jsr   	DECB_CLOSE_FILE

	ldd  	vramStatusStartPtr
	std  	vramProgressTextPtr
	ldy  	#strCaptureDone
	jsr  	SCREENSHOT_TEXT_PRINT_MSG_ATTR

SCREENSHOT_TEXT_RESTORE_EXIT
	lda  	vramOrigBlockMMU
	sta  	[vramGimeRegister]
	lda  	bmpOrigBlockMMU
	sta  	[bmpGimeRegister]

	lds  	origStackPtr
	
	puls  	CC,D,X,Y,U,PC

SCREENSHOT_TEXT_ERROR_DISK_FULL
SCREENSHOT_TEXT_ERROR_OUT_OF_NAMES
	bra  	SCREENSHOT_TEXT_RESTORE_EXIT

; ------------------------------------------------------------------------------------
SCREENSHOT_TEXT_SETUP_BMP_HEADER
	pshs  	U,Y,X,D

	ldd  	#0
	std  	fileSizeAddBuffer
	std  	fileSizeAddBuffer+2

	; Convert 16 GIME-based color palette values into 4-byte 8-bit wide RGB ones for BMP file
	ldx  	#bmpColorPaletteDefs
	ldy  	#rgbGimeConvTable
	ldu  	#gimePalRegsImage
	ldb  	#16
SCREENSHOT_TEXT_NEXT_PALETTE_COLOR
	lda  	,U+
	lsla  					; Shift off unused bit 7
	lsla  					; Shift off unused bit 6
	; First extract the high order color bits from the GIME palette value, and move them into our destination RGB value
	lsla  					; Shift out high order Red bit
	rol  	rgbColorRedOffset,X
	lsla  					; Shift out high order Green bit
	rol  	rgbColorGreenOffset,X
	lsla  					; Shift out high order Blue bit
	rol  	rgbColorBlueOffset,X
	; Then extract the low order ones and shift them into place as well
	lsla  					; Shift out low order Red bit
	rol  	rgbColorRedOffset,X
	lsla  					; Shift out low order Green bit
	rol  	rgbColorGreenOffset,X
	lsla  					; Shift out low order Blue bit
	rol  	rgbColorBlueOffset,X
	; Finally, use our lookup table to scale the 0-3 values to 8-bit wide ones (0, 85, 170, and 255)
	lda  	,X
	lda  	A,Y
	sta  	,X+  				; Store final Blue byte
	lda  	,X
	lda  	A,Y
	sta  	,X+  				; Store final Green byte
	lda  	,X
	lda  	A,Y
	sta  	,X++  				; Store final Red byte and increment over reserved/unused 4th byte
	; X should now be pointing at next BMP palette definition
	decb
	bne  	SCREENSHOT_TEXT_NEXT_PALETTE_COLOR
	
	; Copy full BITMAPFILEHEADER + BITMAPINFOHEADER into sectorBuffer
	ldx  	#bitmapFileHeader
	ldy  	sectorBufferPtr
	ldb  	#bitmapFileHeaderSz
SCREENSHOT_TEXT_SETUP_BMP_HEADER_NEXT
	lda  	,X+
	sta  	,Y+
	decb
	bne  	SCREENSHOT_TEXT_SETUP_BMP_HEADER_NEXT
	sty  	sectorBufferPtr  		; Update sector buffer ptr

	puls  	D,X,Y,U,PC

; ------------------------------------------------------------------------------------
SCREENSHOT_TEXT_COMPRESS_RLE
	pshs  	U,Y,X,D

	ldu  	bmpBufferStartPtr
	ldy  	sectorBufferPtr
SCREENSHOT_TEXT_COMPRESS_RLE_NEW_LINE
	ldx  	#320
SCREENSHOT_TEXT_COMPRESS_RLE_ROW_NEXT_RUN
	clra
	ldb  	,U+
SCREENSHOT_TEXT_COMPRESS_RLE_NEXT_BYTE
	adda  	#2
	leax  	-1,X
	beq  	SCREENSHOT_TEXT_COMPRESS_RLE_END_OF_LINE
	cmpa  	#254
	beq   	SCREENSHOT_TEXT_COMPRESS_RLE_MAX_BLOCK_SIZE_REACHED
	cmpb  	,U+
	beq  	SCREENSHOT_TEXT_COMPRESS_RLE_NEXT_BYTE	
	leau  	-1,U
SCREENSHOT_TEXT_COMPRESS_RLE_MAX_BLOCK_SIZE_REACHED
	bsr  	SCREENSHOT_TEXT_ADD_WORD_BUFFER  	; A should be pixel count byte value, B is the pixel byte to repeat
	bra   	SCREENSHOT_TEXT_COMPRESS_RLE_ROW_NEXT_RUN

SCREENSHOT_TEXT_COMPRESS_RLE_END_OF_LINE
	bsr   	SCREENSHOT_TEXT_ADD_WORD_BUFFER  	; A should be pixel count byte value, B is the pixel byte to repeat
	ldd  	#0
	bsr   	SCREENSHOT_TEXT_ADD_WORD_BUFFER  	; Add End-of-line (EOL) marker ($00 $00)
	cmpu 	bmpBufferEndPtr
	blo  	SCREENSHOT_TEXT_COMPRESS_RLE_NEW_LINE
	sty  	sectorBufferPtr

	puls  	D,X,Y,U,PC

; ------------------------------------------------------------------------
; Entry: D = data word to add to our output buffer
; ------------------------------------------------------------------------
SCREENSHOT_TEXT_ADD_WORD_BUFFER
	std  	,Y++
	cmpy  	sectorBufferEndPtr
	blo  	SCREENSHOT_TEXT_ADD_WORD_BUFFER_SKIP_SECTOR_WRITE
	; If here, current disk buffer is full. If buffer contains BMP header (first sector of file), then defer
	; writing to disk since we need to populate the header's size values with valid data at the end very end
	cmpy  	#headerSectorBuffer+256  
	bne   	SCREENSHOT_TEXT_ADD_WORD_BUFFER_WRITE_SECTOR
	; If here, we just finished filling the header buffer. Migrate the pointers over to the main sectorBuffer
	ldd  	#sectorBuffer
	std  	>diskDataPtr
	inca
	std  	sectorBufferEndPtr
	bra  	SCREENSHOT_TEXT_ADD_WORD_BUFFER_UPDATE_FILESIZE

SCREENSHOT_TEXT_ADD_WORD_BUFFER_WRITE_SECTOR
	; If here, this was a normal sector so write it out to disk
	jsr  	DECB_WRITE_SECTOR
SCREENSHOT_TEXT_ADD_WORD_BUFFER_UPDATE_FILESIZE
	ldy  	#sectorBuffer
	sty  	sectorBufferPtr
	; Add 256 bytes to our running filesize count
	ldd  	fileSizeAddBuffer+1
	addd  	#1
	std  	fileSizeAddBuffer+1
	bcc   	SCREENSHOT_TEXT_ADD_WORD_BUFFER_NO_CARRY	; 3 cycles	
	inc  	fileSizeAddBuffer
SCREENSHOT_TEXT_ADD_WORD_BUFFER_NO_CARRY
SCREENSHOT_TEXT_ADD_WORD_BUFFER_SKIP_SECTOR_WRITE
	rts

; ------------------------------------------------------------------------
; Entry: A = Total border rows to insert
; 	  B = Pixel color number to use
; NOTE:  Original register values will be lost
; ------------------------------------------------------------------------
SCREENSHOT_TEXT_INSERT_RLE_BORDER_ROWS
	pshs  	Y,X,D

	ldy  	sectorBufferPtr
	; Create a 4bpp packed byte containing 2 pixels of the border color to insert
	lslb
	lslb
	lslb
	lslb
	orb  	1,S
	; Now use some stack space for two temporary words containing pre-compressed RLE block values
	lda  	#132  					; 132 pixels
	pshs  	D
	lda  	#254 					; 254 pixels
	pshs  	D
	; Setup our scanline counter
	ldb  	4,S  					; Grab A from the stack
	clra
	tfr  	D,X
SCREENSHOT_TEXT_INSERT_RLE_BORDER_ROWS_NEXT
	ldd  	,S
	bsr  	SCREENSHOT_TEXT_ADD_WORD_BUFFER  	; Adds 254 pixels
	ldd  	,S
	bsr  	SCREENSHOT_TEXT_ADD_WORD_BUFFER  	; Adds 254 pixels
	ldd  	2,S 					
	bsr   	SCREENSHOT_TEXT_ADD_WORD_BUFFER  	; Adds remaining 132 pixels to make 640 total
	ldd 	#0
	bsr   	SCREENSHOT_TEXT_ADD_WORD_BUFFER  	; Adds EOL (End-of-line) marker $00 $00
	leax  	-1,X
	bne 	SCREENSHOT_TEXT_INSERT_RLE_BORDER_ROWS_NEXT
	leas  	4,S  					; Skip over our 4 temp bytes on the stack
	sty  	sectorBufferPtr

	puls  	D,X,Y,PC

; ------------------------------------------------------------------------
SCREENSHOT_TEXT_PRINT_MSG_ATTR
	pshs  	X,D

	ldx  	vramProgressTextPtr
	; First, set the whole status bar row background color to specified value
	lda 	#$20
SCREENSHOT_TEXT_PRINT_MSG_ATTR_CLEAR_NEXT
	ldb  	1,X
	andb  	#%11000000
	orb  	statusBarColorBG
	orb  	statusBarColorFG
	std  	,X++
	cmpx  	vramStatusEndPtr
	blo  	SCREENSHOT_TEXT_PRINT_MSG_ATTR_CLEAR_NEXT

	ldx  	vramProgressTextPtr
SCREENSHOT_TEXT_PRINT_MSG_ATTR_NEXT_CHAR
	lda  	,Y+
	beq  	SCREENSHOT_TEXT_PRINT_MSG_ATTR_DONE
	sta  	,X++
	cmpx  	vramStatusEndPtr
	blo  	SCREENSHOT_TEXT_PRINT_MSG_ATTR_NEXT_CHAR
SCREENSHOT_TEXT_PRINT_MSG_ATTR_DONE
	stx  	vramProgressTextPtr

	puls  	D,X,PC

; ------------------------------------------------------------------------
SCREENSHOT_TEXT_UPDATE_PROGRESS
	pshs  	X,D
	
	ldx  	vramProgressBarPtr
	; Print whole number progress blocks first
	ldb  	progressBarWholeStep
SCREENSHOT_TEXT_UPDATE_PROGRESS_WHOLE_NEXT
	bsr  	SCREENSHOT_TEXT_UPDATE_PROGRESS_APPEND_BLOCK
	decb 
	bne  	SCREENSHOT_TEXT_UPDATE_PROGRESS_WHOLE_NEXT
	; Check if there is enough accumulated remainders to add an extra progress bar block
	ldb  	progressBarRemCount
	addb  	progressBarRemSteps
	cmpb  	screenHeight
	blo  	SCREENSHOT_TEXT_UPDATE_PROGRESS_NO_EXTRA
	bsr  	SCREENSHOT_TEXT_UPDATE_PROGRESS_APPEND_BLOCK  	; Add 1 extra block to compensate for remainders
	subb  	screenHeight
SCREENSHOT_TEXT_UPDATE_PROGRESS_NO_EXTRA
	stb  	progressBarRemCount
	stx  	vramProgressBarPtr
SCREENSHOT_TEXT_UPDATE_PROGRESS_DONE
	puls  	X,D,PC

SCREENSHOT_TEXT_UPDATE_PROGRESS_APPEND_BLOCK
	lda  	1,X
	anda  	#%11111000
	ora 	progressBarColorBG
	sta  	1,X
	leax  	2,X
	rts

; -----------------------------------------------------------------------
	END START