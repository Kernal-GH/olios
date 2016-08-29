
;------------------------------------------------------------
; loader for olios
; olios����ϵͳ������
;
; nasm zhldr.asm -o zhldr
;
; ����޸�ʱ�䣺2011-01-04
;
; ���ز���ϵͳ,��FAT32�������Ŀ¼�в����ں��ļ�������
;
;
; ���������
; bp -> FAT32��������
;
; NOTE:  �������ݴ���ָ��ʹ�õĶμĴ���
;    1. rep movsb        ; es:[di] ds:[si]
;        ��������£�Ŀ�� diʹ�� es�Ĵ�����Դ siʹ�� ds
;
;    2. mov ax, [di]     ; ds:[di]
;       mov ax, [si]     ; ds:[si]
;        ������ͨ�Ĵ���ָ���ʹ�� ds�Ĵ���
;-----------------------------------------------------------



%include    "loader.inc"


        org     LOADER_BASE
        
        jmp     _Startup
        
        align   16
        
GdtTable:
gdt0    DESCRIPTOR  00000000h, 000000h, 00000h
gdt1    DESCRIPTOR  00000000h, 0fffffh, 0c09ah  ; 0��ִ��/���Ĵ����
gdt2    DESCRIPTOR  00000000h, 0fffffh, 0c092h  ; 0����/д�����ݶ�
gdt3    DESCRIPTOR  00000000h, 0fffffh, 0c0fah  ; 3��ִ��/���Ĵ����
gdt4    DESCRIPTOR  00000000h, 0fffffh, 0c0f2h  ; 3����/д�����ݶ�
gdt5    DESCRIPTOR  000b8000h, 00ffffh, 040f2h  ; �Դ��ַ����,R3�ɷ���
gdt6    DESCRIPTOR   TSS_BASE, 000068h, 00089h  ; ����386TSS

GDT_TEMP_LEN        equ     $ - GdtTable



;ѡ���ӣ�Ҳ�������GDTͷ��ƫ��
SelectorCodeR0      equ     gdt1 - GdtTable
SelectorDataR0      equ     gdt2 - GdtTable
SelectorCodeR3      equ     gdt3 - GdtTable + 3     ; Ring3�ɷ���
SelectorDataR3      equ     gdt4 - GdtTable + 3
SelectorVideo       equ     gdt5 - GdtTable + 3
SelectorTss         equ     gdt6 - GdtTable


; 16 λ��

[BITS 16]

    _Startup:
        cli
        xor     ax, ax
        mov     ds, ax
        mov     es, ax
        mov     fs, ax
        mov     ss, ax
        mov     sp, LOADER_STACK_TOP
        sti

        push    ax
        push    _real_start
        retf


    _real_start:
        
        ; ���Դ����Ƿ�֧����չ int 13h���ã���֧�ַ���ʧ��
        
        mov     dl, byte [bp + PhysicalDriverNumber]
        mov     ah, 41h
        mov     bx, 55aah
        int     13h
        jb      _error_disk
        cmp     bx, 0aa55h
        jnz     _error_disk
        test    cx, 1
        jz      _error_disk


        ; ����
        
        push    bp
        call    ClearScreen
        call    InitVideo       ; // FIXME
        pop     bp
        
        pushad
        mov     si, szZhldr
        call    DisplayText
        popad
        
        ; �����ں˵����ڴ�
        
        call    LoadKernel

        push    es
        mov     ax, TEMP_BUFFER_SEG
        mov     es, ax
        xor     edi, edi
        call    GetMemoryRange
        pop     es

        ; ��λϵͳ��������, GDT, IDT, TSS

        call    SetSystemDescriptors

        ; �����ڴ淶Χ��������� LOADER������

        call    SetLoaderParamtersBlock
        
        ; call    InitVideo     ; // FIXME
        
        ;
        ; �����л�������ģʽ
        ;

        push    dword GDT_BASE
        push    dword GDT_LENGTH << 16
        lgdt    [esp + 2]
        add     sp, 8
        
        ; enable A20

        cli
        in      al, 92h
        or      al, 10b
        out     92h, al
        
        mov     eax, cr0
        or      eax, 1
        mov     cr0, eax
        
        jmp     dword SelectorCodeR0:_StartCode32
        
    
    ; ���е��������������ʾ������Ϣ��ͣ��
    
    _error_disk:
        mov     si, szDiskError
        call    DisplayText
        jmp     _pause
        
    _error_fs:
        mov     si, szFsError
        call    DisplayText
        jmp     _pause

    _error_no_kernel:
        mov     si, szNoKernel
        call    DisplayText
        jmp     _pause
        
    _error_move_data:
        mov     si, szMoveError
        call    DisplayText
        jmp     _pause

    _error_check_mem:
        mov     si, szMemError
        call    DisplayText
        jmp     _pause
        
    _pause:
        pause
        jmp     _pause



szZhldr         db  'here is zhldr', 0dh, 0ah, 0
szDiskError     db  'a disk error occured', 0dh, 0ah, 0
szFsError       db  'file system error occured', 0dh, 0ah, 0
szMoveError     db  'transfer data to high memory error', 0dh, 0ah, 0
szMemError      db  'get memory range via e820 error', 0dh, 0ah, 0
szNoKernel      db  'no kernel have been found', 0dh, 0ah, 0



;---------------------------------------------------------------------
; ͨ�� e820�õ��ڴ淶Χ
; ���������
; es:di �ڴ���Ϣ�������ַ��ָ��һ��������
; ȫ�ֱ��� MemoryDescCount ��¼�ҵ����ڴ淶Χ����
;---------------------------------------------------------------------

GetMemoryRange:
        pushad
        xor     ebx, ebx
        
    _loop_e820:
        mov     eax, 0e820h
        mov     ecx, 20
        mov     edx, 534d4150h  ; 'SMAP'
        int     15h
        jc      _error_check_mem
        
        add     di, 20
        inc     dword [MemoryDescCount]
        test    ebx, ebx
        jnz     _loop_e820

        popad
        ret
; GetMemoryRange endp
;---------------------------------------------------------------------



;-----------------------------------------------
; ���¶�λϵͳ�Σ����� GDT IDT TSS
; GDT   ֱ�Ӱ�LOADER�ж���ļ������ȥ����Ҫʱ�ټ�
; IDT   ��ʱ�� 0
; TSS   ��ʱ�� 0
;-----------------------------------------------

SetSystemDescriptors:
        pushad
        push    ds
        push    es

        ; �Ƚ� GDT IDT TSS���ڵ������� 0

        push    SYS_DESC_SEG
        pop     es
        xor     eax, eax
        xor     edi, edi
        mov     ecx, 400h + 800h + 400h
        rep stosb

        ; ��LOADER�ж����GDT�Ƶ�ָ����λ��

        mov     ax, LOADER_SEG
        mov     ds, ax
        mov     esi, GdtTable - LOADER_BASE     ; ����ڶε�ƫ��
        xor     edi, edi
        mov     ecx, GDT_TEMP_LEN
        rep movsb

        pop     es
        pop     ds
        popad
        ret
; SetSystemDescriptors endp
;-----------------------------------------------



;--------------------------------------------------
; ����������������ֹ��ܣ�
; һ  �����ڴ��ַ��Χ�������飬�ѿ��õ��ڴ淶Χ�ŵ�ָ��λ��
;     �γ�һ�� Base Size ��ʽ��ֻ������˫�ֵ�����
; ��  Ϊ�ں�׼��������
;     �������ǰ����˫��ΪARD�����ʵģʽ��ַ����������
;--------------------------------------------------

SetLoaderParamtersBlock:
        pushad
        push    ds
        push    es

        ; �Ƚ�������� ARD������0

        push    LPB_SEG
        pop     es
        xor     eax, eax
        xor     edi, edi
        mov     ecx, 1000h + 400h
        rep stosb

        ; ���½���֮ǰ�õ���ARD����

        xor     ebx, ebx        ; ���������������������
        mov     ecx, [MemoryDescCount]
        push    dword [KernelFileSize]
        mov     ax, TEMP_BUFFER_SEG
        mov     ds, ax
        xor     esi, esi
        mov     ax, ARD_SEG
        mov     es, ax
        xor     edi, edi

    _loop_reset_ard:
        cmp     dword [si + 16], AddressRangeMemory     ; 1
        jnz     _nouse_mem

        ; ��һ�����õ��ڴ淶Χ
        ; �ֱ�ȡ����ʼ��ַ�ͳ��ȵĵ�32λ��������

        inc     ebx
        movsd               ; BaseLow32
        add     si, 4
        movsd               ; LengthLow32
        add     si, 8
        jmp     _next_reset_ard

    _nouse_mem:
        add     esi, 20

    _next_reset_ard:
        dec     ecx
        jnz     _loop_reset_ard

        ; ����������ǰ����˫�ֱַ����ARD����ĵ�ַ�͸���
        ; +10h is KernelFileSize
        ; ������ di�����ݴ���Ҫʹ�� ds�μĴ���

        mov     ax, LPB_SEG
        mov     ds, ax
        xor     edi, edi
        mov     dword [di], ARD_BASE
        mov     [di + 4], ebx
        pop     dword [di + 10h]

        pop     es
        pop     ds
        popad
        ret
; SetLoaderParamtersBlock endp
;--------------------------------------------------



;----------------------------------------
; ȫ�ֱ���
;----------------------------------------
        align   4
RootDirSector       dd  0
CurrentFatSector    dd  0
KernelFileSize      dd  0
MemoryDescCount     dd  0
KernelPrevBase      dd  KERNEL_PRE_BASE
KernelModuleName    db  "ZHOSKRNL   "



;-------------------------------------------------------
; �����ں�
; ��������� bp -> FAT32 ��������
;-------------------------------------------------------

LoadKernel:

        ;
        ; ȡ�ø�Ŀ¼��ʼ����
        ; �÷���ǰ���������� + ��������(������������) + ����FAT��Ĵ�С
        ;

        movzx   eax, byte [bp + Fats]
        mov     ecx, [bp + LargeSectorsPerFat]
        mul     ecx
        add     eax, [bp + HiddenSectors]
        movzx   edx, word [bp + ReservedSectors]
        add     eax, edx
        mov     [RootDirSector], eax
        
        ; 
        ; �� BPB���ó���Ŀ¼�ĵ�һ����
        ;

        mov     dword [CurrentFatSector], 0ffffffffh
        mov     eax, [bp + RootDirFirstCluster]
        cmp     eax, 2              ; ��С�غ�
        jb      _error_fs
        cmp     eax, 0ffffff8h      ; ���غ�
        jnb     _error_fs
        
        
    _loop_root_dir:

        ;
        ; �Ӹ�Ŀ¼��ʼ������eax�� FAT�еĴغ�
        ; �Ѵغ�ת����������
        ;

        push    eax
        sub     eax, 2
        movzx   ebx, byte [bp + SectorsPerCluster]
        mov     si, bx
        mul     ebx
        add     eax, dword [RootDirSector]
        
    _loop_cluster:

        ;
        ; ������Ŀ¼����������ڵĴأ�����ÿһ�������� 8200h
        ; eax ����������
        ;

        mov     bx, 8200h
        mov     di, bx
        mov     cx, 1
        call    ReadSector
        
    _loop_sector:

        ;
        ; ����һ�������е�Ŀ¼���
        ; �Ƚ��Ƿ����ں��ļ�
        ;

        cmp     [di], ch        ; 0
        jz      _error_fs
        mov     cl, 11
        push    si
        mov     si, KernelModuleName
        repz cmpsb
        
        pop     si
        jz      _found_kernel
        
        ; ʹ diָ����һ�����

        add     di, cx
        add     di, 21
        
        cmp     di, bx
        jb      _loop_sector
        
        dec     si              ; si = SectorsPerCluster
        jnz     _loop_cluster
        
        pop     eax
        call    GetNextCluster
        jb      _loop_root_dir
        
        add     sp, 4
        jmp     _error_no_kernel
        
        
    _found_kernel:

        ;
        ; �ҵ��ں��ļ�
        ; ȡ�����Ŀ�ʼ�غŵ� eax��
        ;

        add     sp, 4
        sub     di, 11      ; di -> dir entry

        ; �ȵõ��ں��ļ���С(�ֽ�)

        mov     eax, [di + FileSize]
        mov     [KernelFileSize], eax

        mov     si, [di + FirstClusterOfFileHigh]
        mov     di, [di + FirstClusterOfFileLow]
        mov     ax, si
        shl     eax, 16
        mov     ax, di
        
        cmp     eax, 2
        jb      _error_fs
        cmp     eax, 0ffffff8h
        jnb     _error_fs
        
    _read_cluster:

        ;
        ; ѭ�������ں��ļ������͵��ߵ�ַ
        ; eax ���ں��ļ��Ŀ�ʼ�غ�
        ;

        push    eax
        sub     eax, 2
        movzx   ecx, byte [bp + SectorsPerCluster]
        mul     ecx
        add     eax, [RootDirSector]
        xor     ebx, ebx
        push    es
        push    TEMP_BUFFER_SEG
        pop     es
        call    ReadSector
        pop     es
        
        ;
        ; �����ݴ��͵��ߵ�ַ�ռ�
        ;
        
        mov     ecx, ebx
        mov     esi, TEMP_BUFFER_SEG
        shl     esi, 4
        mov     edi, [KernelPrevBase]
        call    TransferToHighMemory
        jc      _error_move_data        ; this, if int 15h fails
        
        pop     eax
        add     [KernelPrevBase], ebx
        call    GetNextCluster
        jb      _read_cluster
        
    _finish_load:
        ret
; LoadKernel endp
;-------------------------------------------------------



;-------------------------------------------------------
; ����ı����� int 15h, 87h  �����ݴ��͵����ڴ���
; ���������� 6�ÿ�� 8�ֽ�
;
        
blk_mov_dt:
        dw  0, 0, 0, 0      ; α������
        dw  0, 0, 0, 0      ; �������������
        
blk_mov_src:
                dw  0ffffh
blk_src_base    db  00, 00, 01  ; base = 10000h
                db  93h         ; type
                dw  0           ; limit16, base24 = 0
                
blk_mov_dst:
                dw  0ffffh
blk_dst_base    db  00, 00, 10  ;base = 100000
                db  93h
                dw  0
                
        dw  0, 0, 0, 0      ; BIOS CS
        dw  0, 0, 0, 0      ; BIOS DS


;----------------------------------------------------
; �����ݴӵ͵�ַ(< 1M)���͵��ߵ�ַ
; ���������
; esi   Դ��ַ
; edi   Ŀ���ַ
; ecx   ����ĳ���(�ֽ�)
;
; �����
; ����������CF = 1
;----------------------------------------------------

TransferToHighMemory:
        pushad
        mov     eax, esi
        mov     word [blk_src_base], ax
        shr     eax, 16
        mov     byte [blk_src_base + 2], al
        
        mov     eax, edi
        mov     word [blk_dst_base], ax
        shr     eax, 16
        mov     byte [blk_dst_base + 2], al
        
        shr     ecx, 1
        mov     esi, blk_mov_dt
        mov     ax, 8700h
        int     15h
        popad
        ret
; TransferToHighMemory endp
;----------------------------------------------------



;-----------------------------------
; ȡ�� FAT���������һ����
; ���������
; eax   ��ǰ�غ� ID
;
; ����ֵ��
; Cλ��λ������������û����β
;-----------------------------------

GetNextCluster:
        shl     eax, 2
        call    ReadFatSector
        mov     eax, [bx + di]
        and     eax, 0fffffffh
        cmp     eax, 0ffffff8h
        ret
; GetNextCluster endp
;-----------------------------------



;----------------------------------------------------
; ��ȡ�غ��� FAT���ж�Ӧ�������� 7e00h
; ���������
; eax   �غ��� FAT���е�ƫ��(�ֽ�)
;
; ����ֵ��
; di    7e00h
; bx    �����һ��������ƫ��
;----------------------------------------------------

ReadFatSector:
        mov     di, 7e00h
        movzx   ecx, word [bp + BytesPerSector]
        xor     edx, edx
        
        ; eax / �����ֽ������õ��� FAT�����ڵ�����
        ; edx �����������һ��������ƫ��
        
        div     ecx
        
        ; �����������Ѿ������룬ֱ������
        
        cmp     eax, [CurrentFatSector]
        jz      _ret_read_fat_sector
        
        mov     [CurrentFatSector], eax
        
        add     eax, [bp + HiddenSectors]
        movzx   ecx, word [bp + ReservedSectors]
        add     eax, ecx
        
        ; �ж��Ƿ��л FAT��Ŀ
        
        movzx   ebx, word [bp + ExtendedFlags]
        and     bx, 0fh
        jz      __read
        
        cmp     bl, [bp + Fats]
        jnb     _error_fs
        
        push    dx
        mov     ecx, eax
        mov     eax, [bp + LargeSectorsPerFat]
        mul     ebx
        add     eax, ecx
        pop     dx
        
    __read:
        push    dx
        mov     bx, di
        mov     cx, 1
        call    ReadSector
        
        pop     dx
        
    _ret_read_fat_sector:
        mov     bx, dx      ; ����
        ret
; ReadFatSector endp
;----------------------------------------------------



;-----------------------------------------------------
; ������֧�ֺ���������չ int 13h�� 42h
; ���������
; eax   Ҫ���������ľ��Ե�ַ
; es:bx Ŀ���ַ
; cx    ����������
;
; �����
; eax   ��һ�� LBA
; bx    �������ݵ�ĩβ
; cx    0
;-----------------------------------------------------

ReadSector:
        pushad
        
        ; ������̵�ַ���ݰ�
        
        push    dword 0
        push    eax
        push    es
        push    bx
        push    dword 10010h    ; ����ȡһ������
        mov     ah, 42h
        mov     dl, [bp + PhysicalDriverNumber]
        mov     si, sp
        int     13h
        add     sp, 10h
        
        popad
        jb      _error_disk
        add     bx, 200h
        inc     eax
        dec     cx
        jnz     ReadSector
        
        ret
; ReadSector endp
;-----------------------------------------------------



;------------------------------------------------
; ����Ļ������ַ�����ͨ�� int 10h����
; ���������
; si    -> Ҫ��ʾ���ַ����� 0��β
;------------------------------------------------

DisplayText:
        lodsb
        test    al, al
        jz      _ret_display
        
        mov     ah, 0eh
        mov     bx, 7
        int     10h
        jmp     DisplayText
        
    _ret_display:
        ret
; DisplayText endp
;------------------------------------------------
        


;-------------------------------
; ����
;-------------------------------
ClearScreen:
        mov     ax, 600h
        mov     bx, 700h
        mov     cx, 0
        mov     dx, 184fh
        int     10h
        ret
; ClearScreen endp
;-------------------------------



;------------------------------------------------
        align   4
VbeInfoBlock:   times 512 db 0
ModeInfoBlock:  times 256 db 0
PhysicalBasePtr dd  0


;------------------------------------------------
; ��ʼ����ʾ��Ϣ
;------------------------------------------------
InitVideo:

        ;
        ; ȡ��VBE��Ϣ
        ;

        mov     ax, 4f00h
        mov     di, VbeInfoBlock
        int     10h

        ;
        ; ȡ��ģʽ��Ϣ
        ;

        mov     ax, 4f01h
        mov     cx, VIDEO_800_600_16M
        mov     di, ModeInfoBlock
        int     10h

        ;
        ; ����D14��ʹ��ƽ̹������
        ;

        ;mov     ax, 4f02h
        ;mov     bx, VIDEO_800_600_16M + 4000h
        ;mov     di, CrtcInfoBlock
        ;int     10h

        ;
        ; ȡ�õ�ǰģʽ
        ;

        ;xor     ebx, ebx
        ;mov     ax, 4f03h
        ;int     10h
        ;mov     [CurrentVbeMode], ebx

        mov     edi, ModeInfoBlock
        movzx   eax, word [edi + 16]
        ;mov     [BytesPerScanLine], eax    ; 2400
        
        movzx   eax, byte [edi + 25]
        ;mov     [BitsPerPixel], eax        ; 24
        
        mov     eax, [edi + 40]
        mov     [PhysicalBasePtr], eax     ; 0xe0000000

        ret
; InitVideo endp
;------------------------------------------------



;------------------------------------------------------------------;
;------------------------------------------------------------------;
;                                                                  ;
;                         ����ģʽ 32 λ����                          ;
;                                                                  ;
;------------------------------------------------------------------;
;------------------------------------------------------------------;

[BITS 32]

szWelcome           db  'welcome to olios OS', 0ah, 0
szHaveLoadedKernel  db  'zhoskrnl has been loaded to physical address ', 0
szVideoBuf          db  'the vga flat buffer : ', 0


        align   4

CurrentDisplayPosition  dd  (80 * 1 + 0) * 2    ; ��Ļ1��0�У�ÿ�ַ����ֽ�


    _StartCode32:
        cli
        xor     eax, eax
        mov     ax, SelectorDataR0
        mov     ds, ax
        mov     es, ax
        mov     fs, ax
        mov     ss, ax

        mov     ax, SelectorVideo
        mov     gs, ax
        mov     esp, LOADER_STACK_TOP

        push    szWelcome
        call    DisplayString

        ; ��ʾʵģʽ�µõ����ڴ��ַ��Χ������Ϣ

        call    DisplayMemoryRange

        ; ��ELF��ʽ���¶�λ�ں��ļ�,�����Ǽ��ص������ַ��Ҫ���� KSEG0_BASE

        call    AdjustKernelImage

        push    szHaveLoadedKernel
        call    DisplayString
        push    KRNL_PBYSICAL_BASE
        call    DisplayInt
        call    DisplayReturn
        
        ;;;;;;;;;;;;;;;;;;;;;;;;;;
        call    DisplayReturn
        call    DisplayReturn
        call    DisplayReturn
        push    szVideoBuf
        call    DisplayString
        mov     eax, [PhysicalBasePtr]
        push    eax
        call    DisplayInt
        call    DisplayReturn
        ;;;;;;;;;;;;;;;;;;;;;;;;;;

        ; ��PLB�������ں˼��ص������ַ���ڴ��е������ӳ���С���Լ������ڴ��С

        mov     eax, LPB_BASE
        mov     dword [eax + 8], KRNL_PBYSICAL_BASE
        mov     ecx, [KernelImageSize]
        mov     [eax + 0ch], ecx
        mov     ecx, [TotalMemorySize]
        mov     [eax + 14h], ecx
        or      dword [eax], KSEG0_BASE

        ; �����ں����ִ��

        mov     eax, KRNL_PBYSICAL_BASE
        mov     eax, [eax + 18h]    ; entry �����ַ
        sub     eax, KSEG0_BASE     ; ת�������ַ
        jmp     eax
        ret             ; faked ret

    ; ����ִ�е����ͣ��

    _pause_machine:
        pause
        jmp     _pause_machine



;-------------------------------------------------

        align   4

KernelImageSize    dd  0

;-------------------------------------------------
; ��ʵģʽ�¶�����ڴ�ռ���ں�ӳ��ELF��ʽ�ض�λ
; �����ԭӳ���ַ����Ϊ KERNEL_PREV_BASE
; �µ�ִ�������ַ�ڱ���ʱָ����������ELF�ļ���ȡ��
; �ں˱���ʱ�Ļ���ַ���ں˿ռ�֮�ϣ�������ص��͵������ַ
; ��Ҫ��ȥ�ں����û���ַ�ռ�ķֽ�
;-------------------------------------------------

AdjustKernelImage:
        pushad

        mov     ebx, KERNEL_PRE_BASE
        movzx   ecx, word [ebx + 2ch]   ; ����ͷ���еĸ���Ŀ���������ε���Ŀ
        mov     edx, [ebx + 1ch]        ; ����ͷ������ļ�ͷ��ƫ��
        add     edx, ebx                ; ָ�����ͷ��

    _loop_adj:

        ; �ж� Type,Ϊ0�򲻼��������

        mov     edi, [edx]
        or      edi, edi
        jz      _next_adj

        push    ecx
        mov     edi, [edx + 8]      ; VA
        sub     edi, KSEG0_BASE     ; ת�������ڴ�͵�ַ

        mov     ecx, [edx + 10h]    ; Size

        lea     eax, [edi + ecx]
        cmp     eax, [KernelImageSize]
        jb      _small_sec

        mov     [KernelImageSize], eax

    _small_sec:

        mov     esi, [edx + 4]      ; �ļ���ƫ��
        add     esi, ebx            ; �����ļ����ڴ��еĵ�ַ����λ������
        cld
        rep movsb
        pop     ecx

    _next_adj:
        add     edx, 20h
        loop    _loop_adj

        sub     dword [KernelImageSize], KRNL_PBYSICAL_BASE

        popad
        ret
; AdjustKernelImage endp
;-------------------------------------------------



;-------------------------------------------------
; ��ʾ������

        align   4
TotalMemorySize     dd  0
szMemoryRangeTitle  db '  Base       Size',0ah,0
szRamSize           db 'RAM size : ',0

;-------------------------------------------------
; ��ʾʵģʽ��ȡ�õ��ڴ��ַ��Χ��Ϣ
; ��ȡ�÷�Χ�����ĵ�ַ��Ҳ�����ڴ�������
;-------------------------------------------------

DisplayMemoryRange:
        pushad

        push    szMemoryRangeTitle
        call    DisplayString

        ; ��LOADER��������ȡ���ڴ��ַ��Χ����ĵ�ַ�͸���

        mov     eax, LPB_BASE
        mov     esi, [eax]
        mov     ecx, [eax + 4]

    _loop_all_mem_info:
        push    ecx
        push    dword [esi]
        call    DisplayInt
        push    dword [esi + 4]
        call    DisplayInt
        call    DisplayReturn
        pop     ecx

        lodsd
        mov     ebx, eax
        lodsd
        add     ebx, eax
        cmp     ebx, [TotalMemorySize]
        jb      _n_disp_mem_info

        mov     [TotalMemorySize], ebx

    _n_disp_mem_info:
        loop    _loop_all_mem_info

        call    DisplayReturn

        push    szRamSize
        call    DisplayString

        push    dword [TotalMemorySize]
        call    DisplayInt

        call    DisplayReturn

        popad
        ret
; DisplayMemoryRange endp
;-------------------------------------------------



;---------------------------------------------------
; ����Ļ��ǰλ����ʾһλ��ʮ����������
;
; ����ջ���ݲ�����stdcall ���÷�ʽ
;
; ���������
; 1.    Ҫ��ʾ��������ֻʹ�õ���λ������ʾһλ��ʮ������
;---------------------------------------------------

DisplayOneHex:
        push    ebp
        mov     ebp, esp
        pushad

        mov     eax, [ebp + 8]
        and     eax, 0fh

        ; > 9, ��ʾ A - F

        cmp     al, 9
        ja      _disp_hex

        ; �õ�������ַ���0����ASCII��

        add     al, '0'
        jmp     _can_disp

    _disp_hex:

        ; �õ�������ַ���A����ASCII��

        sub     al, 0ah
        add     al, 'A'

    _can_disp:
        mov     ah, 0ch         ; ��ɫ
        mov     edi, [CurrentDisplayPosition]
        mov     [gs:edi], ax
        add     edi, 2

        mov     [CurrentDisplayPosition], edi

        popad
        mov     esp, ebp
        pop     ebp
        ret     4
; DisplayOneHex endp
;---------------------------------------------------



;---------------------------------------------------
; ����Ļ��ǰλ����ʾһ��ʮ����������
;
; ����ջ���ݲ�����stdcall ���÷�ʽ
;
; ���������
; 1.    Ҫ��ʾ������
;---------------------------------------------------

DisplayInt:
        push    ebp
        mov     ebp, esp
        pushad

        mov     ebx, [ebp + 8]
        mov     ecx, 32

        ; ѭ��8����ʾһ��������ÿ��4λ

    _loop_disp_hex:
        sub     ecx, 4
        mov     eax, ebx
        shr     eax, cl
        and     eax, 0fh
        push    ecx

        push    eax
        call    DisplayOneHex

        pop     ecx
        test    ecx, ecx
        jnz     _loop_disp_hex

        ; ���ֺ����'h'���ټ�һ���ո�

        mov     ah, 7
        mov     al, 'h'
        mov     edi, [CurrentDisplayPosition]
        mov     [gs:edi], ax
        add     edi, 4
        mov     [CurrentDisplayPosition], edi

        popad
        mov     esp, ebp
        pop     ebp
        ret     4
; DisplayInt endp
;---------------------------------------------------



;---------------------------------------------------
; ����Ļ��ǰλ����ʾ�ַ�������ָ����ɫ������ 0������0ah����
;
; ����ջ���ݲ�����stdcall ���÷�ʽ
;
; ���������
; 1. ָ��Ҫ��ʾ���ַ���
; 2. ��ɫ
;---------------------------------------------------

DisplayColorString:
        push    ebp
        mov     ebp, esp
        pushad

        mov     esi, [ebp + 8]
        mov     edi, [CurrentDisplayPosition]
        mov     ah, [ebp + 12]         ; ��ɫ

    _loop_char_disp:
        lodsb
        test    al, al
        jz      _ret_disp

        cmp     al, 0ah
        jnz     _disp_str

        ; 0ah,����س�

        push    eax
        mov     eax, edi

        ; ÿ�� 160�ֽڣ����� 160�õ���ǰ���ڵ���
        mov     bl, 160
        div     bl
        and     eax, 0ffh

        ; ������һ�п�ͷ
        inc     eax
        mov     bl, 160
        mul     bl
        mov     edi, eax
        pop     eax
        jmp     _loop_char_disp

    _disp_str:
        mov     [gs:edi], ax
        add     edi, 2
        jmp     _loop_char_disp

    _ret_disp:
        mov     [CurrentDisplayPosition], edi
        popad
        mov     esp, ebp
        pop     ebp
        ret     8
; DisplayColorString endp
;---------------------------------------------------



;---------------------------------------------------
; ����Ļ��ǰλ����ʾ�ַ������ڵװ��֣����� 0������0ah����
;
; ����ջ���ݲ�����stdcall ���÷�ʽ
;
; ���������
; 1. ָ��Ҫ��ʾ���ַ���
;---------------------------------------------------

DisplayString:
        push    ebp
        mov     ebp, esp

        push    dword 0ch
        push    dword [ebp + 8]
        call    DisplayColorString

        mov     esp, ebp
        pop     ebp
        ret     4
; DisplayString endp
;---------------------------------------------------



;---------------------------------
; ����
;---------------------------------
DisplayReturn:

        ; ��ջ�Ϲ���һ����: 0ah, 0

        push    dword 0ah
        push    esp
        call    DisplayString
        pop     eax
        ret
; DisplayReturn endp
;---------------------------------



