*****************************************
* DECB Filesystem Routines 
*****************************************

; Equates

decb_dir_track  		EQU  	17
decb_fat_sector  		EQU  	2
decb_dir_start_sector  	EQU  	3

decb_ext_offset 		EQU 	8
decb_type_offset 		EQU 	11
decb_flag_offset 		EQU 	12
decb_granule_offset 		EQU 	13
decb_rem_bytes_offset 	EQU 	14

decb_type_basic 		EQU 	0
decb_type_data 		EQU 	1
decb_type_exec 		EQU 	2
decb_type_text 		EQU 	3

decb_flag_ascii 		EQU 	$FF
decb_flag_binary 		EQU 	0

diskOpCode 			EQU  	$00EA
diskDriveNum  		EQU  	$00EB
diskTrack  			EQU 	$00EC	
diskSector  			EQU  	$00ED
diskDataPtr 			EQU  	$00EE
diskStatus  			EQU 	$00F0

DSKCON  			EQU  	$C004

; --------------------------------------------------------------------------
; Init DSKCON variables
; Entry: A = drive number to setup for
; --------------------------------------------------------------------------
DSKCON_INIT
	pshs  	D

	sta  	>diskDriveNum

	ldd  	#sectorBuffer
	std  	>diskDataPtr

	ldd  	#decbGranWriteOrder
	std  	decbGranWriteOrderPtr

	puls  	D,PC

; --------------------------------------------------------------------------
DSKCON_READ_SECTOR
	pshs  	A

	sta   	>coco3_slow  	; put coco3 into slow mode for DECB disk access

	; first swap DECB back into address space
	;lda  	#$3C
	;sta  	>mmu_bank4

	clr  	>diskStatus 	; init this to 0 so we can tell if a disk error happened afterwards
	; track and sector values will already be set in calling routines
	lda  	#$02 		; 2 = Read sector operation
	sta  	>diskOpCode
	jsr  	[DSKCON] 	; execute DSKCON command

	; set the floppy motor timer for shutting it off later



	; restore vram blocks to MMU
	;lda  	#$31
	;sta  	>mmu_bank4

	sta  	>coco3_fast 	; restore coco3 into fast mode 
	
	ldb  	>diskStatus

	puls  	A,PC 

; --------------------------------------------------------------------------
DSKCON_WRITE_SECTOR
	pshs  	A

	sta   	>coco3_slow  	; put coco3 into slow mode for DECB disk access

	; first swap DECB back into address space
	;lda  	#$3C
	;sta  	>mmu_bank4

	clr  	>diskStatus 	; init this to 0 so we can tell if a disk error happened afterwards
	; track and sector values will already be set in calling routines
	lda  	#$03 		; 3 = Write sector operation
	sta  	>diskOpCode
	jsr  	[DSKCON] 	; execute DSKCON command

	; set the floppy motor timer for shutting it off later




	; restore vram blocks to MMU
	;lda  	#$31
	;sta  	>mmu_bank4



	sta  	>coco3_fast 	; restore coco3 into fast mode 

	puls  	A,PC 


; --------------------------------------------------------------------------
; 1) Fills 68 byte array you point to with granule map from drive specified.
; 2) counts up how many granules are free 
; Entry: Y = points to FAT array to fill 
; 	drive = set to correct drive to access 
; Exit:  everything preserved 
; 	freeGranules gets set 
; --------------------------------------------------------------------------
DECB_GET_FAT
	pshs 	D,X,Y,U 

	lda 	#decb_dir_track
	sta 	>diskTrack
	lda 	#decb_fat_sector
	sta 	>diskSector 
	jsr 	DSKCON_READ_SECTOR
	bcs  	DECB_GET_FAT_DISK_ERROR_EXIT

	ldu 	#sectorBuffer
	ldx 	#68
	clrb 
	; Y is pointing to FAT array to fill 
DECB_GET_FAT_NEXT_GRANULE
	lda 	,U+
	sta 	,Y+ 		; add to granule map 
	cmpa 	#$FF 	; $FF means granule is free
	bne 	DECB_GET_FAT_NOT_FREE
	incb 
DECB_GET_FAT_NOT_FREE
	leax 	-1,X 
	bne 	DECB_GET_FAT_NEXT_GRANULE
	stb 	freeGranules
	andcc  #$FE  		; clear carry to show successfully grabbed FAT 
DECB_GET_FAT_DISK_ERROR_EXIT
	puls 	U,Y,X,D,PC 

; ---------------------------------------------------------------------------
DECB_FAT_FIND_EMPTY_GRANULE
	pshs  	Y,X,D

	ldx  	#decbGranMapDest
	ldy  	decbGranWriteOrderPtr
	lda  	decbFileCurGranuleNum
DECB_FAT_FIND_EMPTY_GRANULE_CHECK_NEXT
	cmpa  	#68
	bhs  	DECB_FAT_FIND_EMPTY_GRANULE_NONE_LEFT
	ldb  	A,X
	cmpb  	#$FF
	beq  	DECB_FAT_FIND_EMPTY_GRANULE_FOUND
	inca
	bra 	DECB_FAT_FIND_EMPTY_GRANULE_CHECK_NEXT

DECB_FAT_FIND_EMPTY_GRANULE_FOUND
	sta  	,S  				; Update A on the stack with found granule number
	sta  	,Y+  				; Add granule to our write list for modifying FAT when closing file
	sty  	decbGranWriteOrderPtr
	inca
	sta  	decbFileCurGranuleNum 	; Increment for the next one, if needed
	clrb  					; Clear carry flag
	puls  	D,X,Y,PC

DECB_FAT_FIND_EMPTY_GRANULE_NONE_LEFT
	orcc  	#1
	puls  	D,X,Y,PC	

 IFDEF use_new_write_map
; ---------------------------------------------------------------------------
; Entry: B = granule number to start searching at
; Exit: B = size of empty block found, blockGranuleStart = starting granule of empty block
; ---------------------------------------------------------------------------
DECB_FAT_FIND_EMPTY_BLOCK
	pshs 	A

DECB_FAT_FIND_EMPTY_BLOCK_NEXT
	lda  	B,Y
	cmpa  	#$FF
	beq  	DECB_FAT_FIND_EMPTY_BLOCK_FOUND_START
	incb
	cmpb  	#68
	blo  	DECB_FAT_FIND_EMPTY_BLOCK_NEXT
	orcc 	#1  		; Set carry since we reached end without finding available entry
	puls  	A,PC

DECB_FAT_FIND_EMPTY_BLOCK_FOUND_START
	stb  	blockGranuleStart
DECB_FAT_FIND_EMPTY_BLOCK_NEXT_EMPTY
	incb 
	cmpb  	#68
	bhs  	DECB_FAT_FIND_EMPTY_BLOCK_END
	lda  	B,Y
	cmpa  	#$FF
	beq  	DECB_FAT_FIND_EMPTY_BLOCK_NEXT_EMPTY
DECB_FAT_FIND_EMPTY_BLOCK_END
	subb  	blockGranuleStart
	andcc 	#$FE  		; Clear carry to show found empty space of some size
	puls  	A,PC

; ---------------------------------------------------------------------------
DECB_BUILD_WRITE_MAP
	pshs 	D,X

	ldb  	freeGranules
	cmpb  	neededGranules
	blo  	DECB_BUILD_WRITE_MAP_ERROR_INSUFFICIENT_SPACE

	ldx  	#decbGranWriteOrder
	stx  	decbGranWriteOrderCurPtr
	clrb  							; Start at granule 0
DECB_BUILD_WRITE_MAP_NEXT_BLOCK
	bsr  	DECB_FAT_FIND_EMPTY_BLOCK  			; Find the start of next empty block
	; Now check if the size of granule blocks is enough for our file
	cmpb  	neededGranules
	blo  	DECB_BUILD_WRITE_MAP_CUR_BLOCK_TOO_SMALL
	; If here, we found a contiguous block of free granules that will fit our file
	ldb  	blockGranuleStart
	bra  	DECB_BUILD_WRITE_MAP_NEXT_MANUAL  		; Start from beginning of our contiguous block and save to map

DECB_BUILD_WRITE_MAP_CUR_BLOCK_TOO_SMALL
	addb  	blockGranuleStart
	cmpb  	#68
	blo  	DECB_BUILD_WRITE_MAP_NEXT_BLOCK
	; If here, no contigous block of granules is large enough for our file. Use first-come-first-serve method
	clrb
DECB_BUILD_WRITE_MAP_NEXT_MANUAL
	lda  	B,Y
	cmpa  	#$FF
	bne  	DECB_BUILD_WRITE_MAP_CHECK_NEXT
	stb  	,X+
DECB_BUILD_WRITE_MAP_CHECK_NEXT
	incb
	cmpb  	#68
	blo  	DECB_BUILD_WRITE_MAP_NEXT_MANUAL
	
	clra  			; Clear carry flag
	puls  	D,X,PC

DECB_BUILD_WRITE_MAP_ERROR_INSUFFICIENT_SPACE
	orcc  	#1
	puls  	D,X,PC
 ENDC

 IFDEF use_old_write_map
; -------------------------------------------------------------------------------------------
; Create map of which granules to write to. First tries to find a contiguous block, if not, 
; starts at granule 0 and uses free granules as it finds them.
; Entry: decbGranMapDest is filled with granule map of disk to write to 
; 	decbFilesizeGran = how many granules we need to write 
; Exit:  decbGranWriteOrder is filled with list of granules to write to in order 
; 	Carry clear if successful, Carry set on fail.
; -------------------------------------------------------------------------------------------
DECB_BUILD_WRITE_MAP
	pshs 	D,X,Y,U 

	ldy 	#decbGranMapDest+$22 	; start after track 17 (granule 34)
	ldu 	#tempWord
DECB_BUILD_WRITE_MAP_MOVE_PTR_NEXT_GRANULE
	ldb 	decbFilesizeGran
	sty 	,U
DECB_BUILD_WRITE_MAP_GRANULES_NEXT
	cmpy 	#decbGranMapDest+68
	bhs 	DECB_BUILD_WRITE_MAP_CHECK_BEFORE_17
	lda 	,Y+
	cmpa 	#$FF 
	bne 	DECB_BUILD_WRITE_MAP_MOVE_PTR_NEXT_GRANULE
	decb 
	bne 	DECB_BUILD_WRITE_MAP_GRANULES_NEXT
	ldd 	,U
	subd 	#decbGranMapDest

	ldx 	#decbGranWriteOrder
	lda 	decbFilesizeGran 	; our counter 
DECB_BUILD_WRITE_MAP_ORDER_NEXT
	stb 	,X+
	deca 	
	beq 	DECB_BUILD_WRITE_MAP_MARK_END
	incb 
	bra 	DECB_BUILD_WRITE_MAP_ORDER_NEXT

DECB_BUILD_WRITE_MAP_CHECK_BEFORE_17
	ldy 	#decbGranMapDest+$22 	; start at the last granule before track 17 starts (remember we PRE decrement before LDA value)

DECB_BUILD_WRITE_MAP_MOVE_PTR_PREV_GRANULE
	ldb 	decbFilesizeGran
	sty 	,U
DECB_BUILD_WRITE_MAP_GRANULES_PREV
	cmpy 	#decbGranMapDest
	bls 	DECB_BUILD_WRITE_MAP_NO_CONSECUTIVE
	lda 	,-Y
	cmpa 	#$FF
	bne 	DECB_BUILD_WRITE_MAP_MOVE_PTR_PREV_GRANULE
	decb 
	bne 	DECB_BUILD_WRITE_MAP_GRANULES_PREV
	ldd 	,U 
	subd 	#decbGranMapDest+1 	; +1 because we didnt update ,U after pre decrement 
	
	ldx 	#decbGranWriteOrder
	lda 	decbFilesizeGran 	; our counter 
DECB_BUILD_WRITE_MAP_ORDER_PREV
	cmpa 	#$01
	beq 	DECB_BUILD_WRITE_MAP_SAVE_LAST
	; if we are here, than theres more than 1 to write 
	bitb 	#$01
	bne 	DECB_BUILD_WRITE_MAP_ODD_START
	; if we are here, theres more than 1 granule to write and we start on even numbered granule 
	stb 	,X+
	decb 
	deca 
	cmpa 	#$01
	beq  	DECB_BUILD_WRITE_MAP_SAVE_LAST
	; since theres more than 1 granule left, we can continue as though we started on odd number 

DECB_BUILD_WRITE_MAP_ODD_START
	; if we are here, we are starting on an odd numbered granule 
	decb 

DECB_BUILD_WRITE_MAP_FULL_TRACK
	; on even numbered granule so write 2 granules in order on 1 track 
	stb 	,X+
	incb 
	stb 	,X+
	suba 	#2 	; decrement counter by 2 
	beq 	DECB_BUILD_WRITE_MAP_MARK_END
	cmpa 	#2 	; do we have more than 2 granules left to write?
	blo 	DECB_BUILD_WRITE_MAP_FINAL_PREV_GRANULE
	subb 	#3
	bra 	DECB_BUILD_WRITE_MAP_FULL_TRACK

DECB_BUILD_WRITE_MAP_FINAL_PREV_GRANULE
	subb 	#2
DECB_BUILD_WRITE_MAP_SAVE_LAST
	stb 	,X+
	bra 	DECB_BUILD_WRITE_MAP_MARK_END

DECB_BUILD_WRITE_MAP_NO_CONSECUTIVE
; just start at 0 and fill them as we find them 
	ldy 	#decbGranMapDest
	ldx 	#decbGranWriteOrder
	ldb 	decbFilesizeGran
	stb 	tempByte 	; use as a counter 
	clrb 
	bra 	DECB_BUILD_WRITE_MAP_SKIP_INC_STUFF 	; skip check/inc stuff for the first time
DECB_BUILD_WRITE_MAP_GET_NEXT_FREE
	cmpb 	#68
	bhs 	DECB_BUILD_WRITE_MAP_ERROR
	incb 
DECB_BUILD_WRITE_MAP_SKIP_INC_STUFF
	lda 	B,Y
	cmpa 	#$FF
	bne 	DECB_BUILD_WRITE_MAP_GET_NEXT_FREE
	; save free granule we found to write array 
	stb 	,X+
	dec 	tempByte 
	bne 	DECB_BUILD_WRITE_MAP_GET_NEXT_FREE

DECB_BUILD_WRITE_MAP_MARK_END
	lda 	#$FF 	; use this to mark end since it cant be a real granule number 
	sta 	,X
	clra
	bra 	DECB_BUILD_WRITE_MAP_EXIT

DECB_BUILD_WRITE_MAP_ERROR
	; something went wrong 
	lda 	#$01
DECB_BUILD_WRITE_MAP_EXIT 
	lsra 
	puls 	U,Y,X,D,PC 

 ENDC

; -------------------------------------------------------------------------------------------
; write out a new FAT sector from decbGranWriteOrder array
; Entry: U = pointer to where you want to write a full 256 bytes FAT sector 
; Exit: 	all things preserved. granule map pointed to by U modified accordingly
; -------------------------------------------------------------------------------------------
DECB_GENERATE_NEW_GRANULE_MAP
	pshs 	D,X 

	ldx 	#decbGranWriteOrder
DECB_GENERATE_NEW_GRANULE_MAP_NEXT
	lda 	,X+
	cmpx  	decbGranWriteOrderPtr
	bhs  	DECB_GENERATE_NEW_GRANULE_MAP_LAST
	ldb 	,X
	stb 	A,U 
	bra 	DECB_GENERATE_NEW_GRANULE_MAP_NEXT

DECB_GENERATE_NEW_GRANULE_MAP_LAST
	ldb 	decbFileLastSectorNum 	
	decb  			; Undo the auto-increment we do after a sector write to get last sector number written to
	cmpb 	#10
	blo 	DECB_GENERATE_NEW_GRANULE_MAP_NO_SUBTRACT
	subb 	#9
DECB_GENERATE_NEW_GRANULE_MAP_NO_SUBTRACT
	andb 	#%00001111 	; strip high 4 bits just in case something weird happened 
	orb 	#%11000000 	; marks last granule in file in FAT 
	stb 	A,U 

	puls 	X,D,PC 

; -------------------------------------------------------------------------------------------
; (does not do any settings checks. assumes there is a valid DECB disk setup and inserted)
; Exit: on fail to find free entry, carry set, all registers preserved
; -------------------------------------------------------------------------------------------
DECB_FIND_FREE_DIR_ENTRY
	pshs 	U,D 

	lda 	#decb_dir_track
	sta 	>diskTrack
	lda 	#decb_dir_start_sector
DECB_FIND_FREE_DIR_ENTRY_NEXT_SECTOR
	sta 	>diskSector
	jsr 	DSKCON_READ_SECTOR
	ldu 	#sectorBuffer 
DECB_FIND_FREE_DIR_ENTRY_NEXT_ENTRY
	lda 	,U 		; get the first byte in entry
	beq 	DECB_FIND_FREE_DIR_ENTRY_FOUND_KILLED
	cmpa 	#$FF
	beq 	DECB_FIND_FREE_DIR_ENTRY_FOUND_EMPTY
	leau 	32,U 
	cmpu 	#sectorBuffer+256
	blo 	DECB_FIND_FREE_DIR_ENTRY_NEXT_ENTRY
	lda 	>diskSector 
	inca 
	cmpa 	#11
	bls 	DECB_FIND_FREE_DIR_ENTRY_NEXT_SECTOR
	; if here, there are no free entries 
	orcc 	#1 	; set carry for error/not found 
	puls 	D,U,PC 	; return 

DECB_FIND_FREE_DIR_ENTRY_FOUND_KILLED
DECB_FIND_FREE_DIR_ENTRY_FOUND_EMPTY
	ldb  	>diskSector
	stb  	decbFileEntrySector
	stu  	decbFileEntryBufferPtr
	clra 		; clear carry flag
	puls  	D,U,PC

; -------------------------------------------------------------------------------------------
; Search for a filename match on specified DECB disk directory 
; Entry: Y = pointer to string of 11-character DECB space-padded filename to search for 
; Exit: success, carry clear. U = points to position in sectorBuffer where file was found. track and sector variables 
; 	will contain location where file was found 
; 	fail, carry set. everything preserved 
; -------------------------------------------------------------------------------------------
DECB_FIND_FILENAME 
	pshs 	D,X,Y,U

	lda 	#decb_dir_track
	sta 	>diskTrack
	lda 	#decb_dir_start_sector
DECB_FIND_FILENAME_NEXT_SECTOR
	sta 	>diskSector 
	jsr 	DSKCON_READ_SECTOR
	ldu 	#sectorBuffer
DECB_FIND_FILENAME_NEXT_ENTRY
	ldy 	4,S `	; grab pointer to filename to search for from stack 
	leax 	,U  
	ldb 	#11 	; should always be 11 characters to check 
DECB_FIND_FILENAME_NEXT_CHAR
	lda 	,X+
	cmpa 	,Y+
	bne	DECB_FIND_FILENAME_CUR_ENTRY_MISMATCH
	decb 
	bne 	DECB_FIND_FILENAME_NEXT_CHAR
	; if we are here, then success !!
	; clear carry for success, track and sector variables will contain location where file was found 
	; dont restore U register so it will contain the offset in 256 sector buffer where filename begins 
	andcc 	#%11111110 	; clear carry for success 
	puls 	Y,X,D 
	leas 	2,S 	; skip U on the stack 
	rts 		; return 

DECB_FIND_FILENAME_CUR_ENTRY_MISMATCH
	leau 	32,U  		; increment to next entry 
	cmpu 	#sectorBuffer+256
	blo 	DECB_FIND_FILENAME_NEXT_ENTRY
	; setup to get the next sector 
	lda 	>diskSector 
	inca 
	cmpa 	#11
	bls 	DECB_FIND_FILENAME_NEXT_SECTOR
DECB_FIND_FILENAME_NO_MATCH
	orcc 	#1 	; set carry flag for fail 
	puls 	U,Y,X,D,PC 	; restore everything and return 

; -------------------------------------------------------------------------------------------
; Set the "track" and "sector" variables based on granule number
; Entry: A = granule to use to set variables 
; Exit: A = new track, B = new sector 
; -------------------------------------------------------------------------------------------
DECB_GET_TRACK_SECTOR_FROM_GRANULE
	lsra 		; assumes A contains granule number 
	bcc 	DECB_GET_TRACK_SECTOR_FROM_GRANULE_EVEN
	ldb 	#10
	bra 	DECB_GET_TRACK_SECTOR_FROM_GRANULE_SAVE

DECB_GET_TRACK_SECTOR_FROM_GRANULE_EVEN
	ldb 	#1
DECB_GET_TRACK_SECTOR_FROM_GRANULE_SAVE
	cmpa 	#17
	blo 	DECB_GET_TRACK_SECTOR_FROM_GRANULE_NO_EXTRA
	inca 
DECB_GET_TRACK_SECTOR_FROM_GRANULE_NO_EXTRA
	rts

; -------------------------------------------------------------------------------------------
DECB_WRITE_SECTOR
	pshs  	D

	ldb  	>diskSector
	cmpb 	#10
	beq  	DECB_WRITE_SECTOR_GET_NEW_GRANULE
	cmpb  	#19
	beq  	DECB_WRITE_SECTOR_GET_NEW_GRANULE
	; If here, our next sector write is still within the current granule we are working on
DECB_WRITE_SECTOR_PERFORM_WRITE
	jsr  	DSKCON_WRITE_SECTOR
	inc 	>diskSector
	clra  			; Clear carry flag
DECB_WRITE_SECTOR_EXIT
	puls  	D,PC

DECB_WRITE_SECTOR_GET_NEW_GRANULE
	jsr  	DECB_FAT_FIND_EMPTY_GRANULE
	bcs  	DECB_WRITE_SECTOR_EXIT  	; Out of granules. Carry is set already, and so just exit
	; If here, we found another free granule
	bsr  	DECB_GET_TRACK_SECTOR_FROM_GRANULE
	std  	>diskTrack
	bra   	DECB_WRITE_SECTOR_PERFORM_WRITE

; -------------------------------------------------------------------------------------------
; Entry: X = Destination filename
; -------------------------------------------------------------------------------------------
DECB_CLOSE_FILE
	pshs  	U,Y,X,D

	ldu  	#sectorBuffer
	stu  	>diskDataPtr
	ldy  	#decbGranMapDest
	ldb  	#68
DECB_CLOSE_FILE_COPY_FAT_NEXT
	lda  	,Y+
	sta  	,U+
	decb 
	bne  	DECB_CLOSE_FILE_COPY_FAT_NEXT
	ldb  	#256-68
	clra
DECB_CLOSE_FILE_FAT_SECTOR_PAD_NEXT
	sta  	,U+
	decb 
	bne  	DECB_CLOSE_FILE_FAT_SECTOR_PAD_NEXT

	ldu  	#sectorBuffer
	jsr  	DECB_GENERATE_NEW_GRANULE_MAP

	lda  	#decb_dir_track
	ldb  	#decb_fat_sector
	std  	>diskTrack
	jsr   	DSKCON_WRITE_SECTOR

	ldb  	decbFileEntrySector
	stb  	>diskSector
	jsr  	DSKCON_READ_SECTOR

	ldy  	decbFileEntryBufferPtr
	ldb  	#11
DECB_CLOSE_FILE_WRITE_FILENAME_NEXT
	lda  	,X+
	sta  	,Y+
	decb  
	bne   	DECB_CLOSE_FILE_WRITE_FILENAME_NEXT

	lda  	#2  	; File type flag
	ldb  	#0  	; ASCII flag (0 = binary)
	std  	,Y++
	lda  	decbGranWriteOrder
	sta  	,Y+  	; First granule in file
	ldd  	decbFileBytesLastSector
	std  	,Y  	; Number of bytes used in last sector of file

	jsr   	DSKCON_WRITE_SECTOR

	puls 	D,X,Y,U,PC

*************************************************
; Variables section 
; DECB variables 

sectorBuffer  		RMB  	256
headerSectorBuffer		RMB  	256

blockGranuleStart   		RMB  	1
decbGranWriteOrder 		RMB 	69 	; 68 granules, +1 for NULL terminator byte 
decbGranWriteOrderPtr  	RMB  	2

freeGranules 			FCB 	$00
neededGranules 		FCB 	$00

decbGranMapDest 		FILL 	$FF,68

decbFileCurGranuleNum  	FCB  	0
decbFileEntrySector		RMB  	1
decbFileEntryBufferPtr 	RMB  	2
decbFileStartGranule  	RMB  	1
decbFileLastSectorNum  	RMB  	1
decbFileBytesLastSector	RMB  	2



