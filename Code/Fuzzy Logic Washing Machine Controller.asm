; ========================================
; Fuzzy Logic Washing Machine Controller (8086 Assembly)
; ========================================

;============================= NEW RULE BASE =============================       
; Rule 0 - If Load is small AND Dirtiness is light         ? Spin Speed: Low,   Duration: Short
; Rule 1 - If Load is medium AND Fabric is normal          ? Spin Speed: Medium, Duration: Medium
; Rule 2 - If Load is large AND Fabric is tough            ? Spin Speed: High,   Duration: Long

; Rule 3 - If Fabric is delicate AND Temperature is cold   ? Spin Speed: Low     (gentle + fragile)
; Rule 4 - If Fabric is tough AND Temperature is hot       ? Spin Speed: High    (strong fabric, fast spin)

; Rule 5 - If Dirtiness is heavy AND Temperature is warm   ? Duration: Long      (heavy dirt + effective temp)
; Rule 6 - If Dirtiness is medium AND Load is medium       ? Duration: Medium    (balanced case)
; Rule 7 - If Dirtiness is light AND Fabric is normal      ? Duration: Short     (clean + average fabric)

; Rule 8 - If Load is large AND Temperature is cold        ? Duration: Long      (large loads in cold water clean slowly)
; Rule 9 - If Load is small AND Fabric is delicate         ? Spin Speed: Low     (fragile, light load)

;Sample combinations for dynamic outputs:
;   Duration:
;       l = 3, f = 2, d = 1, t = 1   , fired rules: 7, 8, duration: 3150 sec or  52.5 min
;       l = 2, f = 2, d = 3, t = 2   , fired rules: 1, 5, duration: 3810 sec or  63.5 min
      
.MODEL SMALL
.STACK 100H

.DATA
    ; Input states (0=not pressed, 1=pressed)
    temp_state      DB 0    ; 1=cold 20 C, 2=warm 40 C , 3=hot 60 C
    load_state      DB 0    ; 1=small, 2=medium, 3=large
    fabric_state    DB 0    ; 1=delicate, 2=normal, 3=tough
    dirt_state      DB 0    ; 1=light, 2=medium, 3=heavy
    
    ; Control buttons
    start_pressed   DB 0
    stop_pressed    DB 0
    system_running  DB 0
    
    ; Output values
    spin_speed_val  DW 0   ; Final spin speed (400-1200)
    duration_val    DW 0    ; Final duration in seconds (e.g 4500)

    ; sec val
    duration_sec    DB 0
    duration_min    DB 0
    duration_hr    DB 0
    
    ; Fuzzy rule results (strength of each rule 0-100)  
    rule_strength   DB 10 DUP(0)
    
    ; INPUT Port Addresses
    
    TEMP_PORT       EQU 30H
    FABRIC_PORT     EQU 30H

    LOAD_PORT       EQU 32H
    DIRT_PORT       EQU 32H

    CONTROL_PORT    EQU 30H

    MACHINE_TEMP_PORT EQU 34H

    ; ===== INPUT Control Ports =====
    PORT_CON2 EQU 36H

    ;====LCD Ports========
    PORT_C1 EQU 24H
    PORT_B1 EQU 22H
    PORT_CONTROL EQU 26H
    PORT_A1 EQU 20H 
    
    ;====LCD PORTS VALUE====
    PORTA_VAL DB 0
    PORTB_VAL DB 0
    PORTC_VAL DB 0  
    MYSTR	DB	"HELLO WORLD$"
    NUM_BUF DB 6 DUP('$')
    SPIN_STR DB 'SSPIN:$',0
    RPM_STR DB ' RPM$', 0
    TIME_STR    DB 'Time:$',0  
    S_STR    DB ' S$',0 
    
    ; Numerator and Denominator of spin_speed(why word? because each are equalled to AX or CX)
    spin_numerator DW 0;
    spin_denominator DW 0;
    
    ; Numerator and Denominator of time 
    time_numerator DW 0;
    time_denominator DW 0;


    ;===================== TIMER MEMORY =====================

    ; ===== OUTPUT Control Ports =====
    PORT_CON1 EQU 26H
    PORT_CON3 EQU 46H
    PORT_CON4 EQU 56H

    ; === PPI 3:  ===
    PORTA3 EQU 40H    
    PORTB3 EQU 42H     
    PORTC3 EQU 44H
    
    
    ; === PPI 4:  ===
    PORTA4 EQU 50H    
    PORTB4 EQU 52H    
    PORTC4 EQU 54H

    SEG_TABLE   DB 3FH, 06H, 5BH, 4FH, 66H, 6DH, 7DH, 07H, 7FH, 6FH

    ;===================== LED AND BUZZER MEMORY =====================
    ; LED_BLUE (PA0) = It blinks after start until end
    ; LED_RED (PA1) = before starting and when getting inputs, this one is on
    ; BUZZER (PA2) = buzzer is enabled after timeout.

    LED_BUZZER_PORT EQU 20H ; LED_RED = before starting and when getting inputs, this one is on

    ;===================== TEMP CONTROL =====================
    temp_sec_alert DB 0 ; consistent time after temp_alerted stayed 1  (after 5 seconds, we would halt)
    temp_alerted DB 0 ; 1 if a temp alert happened 0 if not

.CODE
MAIN PROC
    MOV AX, @DATA
    MOV DS, AX
    
    CALL INIT_SYSTEM
    
MAIN_LOOP:
; Turning on RED LED
    CALL LED_RED_ON

    CALL READ_INPUTS
    CALL CHECK_START_BUTTON
    
    CMP system_running, 1

    JE PROCESS_FUZZY
    JMP MAIN_LOOP
    
PROCESS_FUZZY:
    ; Turning off red led
    CALL LED_RED_OFF

    ; Turning on blue led until timeout
    CALL LED_BLUE_ON

    CALL FUZZY_INFERENCE

    CALL SEND_OUTPUTS
    
STOP_SYSTEM:
    CALL RESET_OUTPUTS

    CALL LED_BLUE_OFF
    CALL BUZZER_ON
    CALL DELAY_1SEC
    ; Turning off the buzzer when system restarting
    CALL BUZZER_OFF

    JMP MAIN_LOOP
MAIN ENDP


; Initialize system
INIT_SYSTEM PROC
    ; Clear all states
    MOV temp_state, 0
    MOV load_state, 0
    MOV fabric_state, 0
    MOV dirt_state, 0

    MOV spin_speed_val, 0
    MOV duration_val, 0
    MOV duration_hr, 0
    MOV duration_min, 0
    MOV duration_sec, 0

    MOV start_pressed, 0
    MOV stop_pressed, 0
    MOV system_running, 0

    MOV temp_alerted, 0
    MOV temp_sec_alert, 0
    
    ; Initialize PPI control registers
    CALL INIT_PPI

    
    RET
INIT_SYSTEM ENDP

LED_RED_ON PROC
    PUSH AX

    MOV AL, 02H
    OUT LED_BUZZER_PORT, AL

    POP AX
    RET
LED_RED_ON ENDP

LED_RED_OFF PROC
    PUSH AX

    MOV AL, 00H
    OUT LED_BUZZER_PORT, AL

    POP AX
    RET
LED_RED_OFF ENDP

LED_BLUE_ON PROC
    PUSH AX

    MOV AL, 01H
    OUT LED_BUZZER_PORT, AL

    POP AX
    RET
LED_BLUE_ON ENDP

LED_BLUE_OFF PROC
    PUSH AX

    MOV AL, 00H
    OUT LED_BUZZER_PORT, AL

    POP AX
    RET
LED_BLUE_OFF ENDP

BUZZER_ON PROC
    PUSH AX

    MOV AL, 04H
    OUT LED_BUZZER_PORT, AL

    POP AX
    RET
BUZZER_ON ENDP

BUZZER_OFF PROC
    PUSH AX

    MOV AL, 00H
    OUT LED_BUZZER_PORT, AL

    POP AX
    RET
BUZZER_OFF ENDP

INIT_PPI PROC
    PUSH AX

    MOV AL, 92H
    OUT PORT_CON2, AL
    
    MOV AL, 80H
    OUT PORT_CON1, AL
    OUT PORT_CON3, AL
    OUT PORT_CON4, AL

    POP AX
    RET
INIT_PPI ENDP

READ_INPUTS PROC 
    
    PUSH AX
    PUSH DX     
    
TEMP:
    ; Read temperature buttons
    MOV DX, TEMP_PORT
    IN AL, DX

    TEST AL, 01H 
    JZ SET_TEMP1

    TEST AL, 02H 
    JZ SET_TEMP2

    TEST AL, 04H 
    JZ SET_TEMP3 

    JMP TEMP  
    
SET_TEMP1:   
    CALL DELAY20 
    IN AL, DX  
    TEST AL, 01H
    JNZ TEMP 
    MOV temp_state, 1
    JMP LOAD   
    
SET_TEMP2:   
    CALL DELAY20 
    IN AL, DX  
    TEST AL, 02H  
    JNZ TEMP 
    MOV temp_state, 2
    JMP LOAD 
    
SET_TEMP3:   
    CALL DELAY20 
    IN AL, DX  
    TEST AL, 04H 
    JNZ TEMP 
    MOV temp_state, 3
    JMP LOAD

    
LOAD:
    ; Read load buttons
    MOV DX, LOAD_PORT
    IN AL, DX

    TEST AL, 01H 
    JZ SET_LOAD1 

    TEST AL, 02H 
    JZ SET_LOAD2

    TEST AL, 04H 
    JZ SET_LOAD3 

    JMP LOAD 
    
SET_LOAD1:   
    CALL DELAY20 
    IN AL, DX  
    TEST AL, 01H
    JNZ LOAD 
    MOV load_state, 1
    JMP FABRIC  
    
SET_LOAD2:   
    CALL DELAY20 
    IN AL, DX  
    TEST AL, 02H  
    JNZ LOAD 
    MOV load_state, 2
    JMP FABRIC 
    
SET_LOAD3:   
    CALL DELAY20 
    IN AL, DX  
    TEST AL, 04H 
    JNZ LOAD 
    MOV load_state, 3
    JMP FABRIC 
    
    
     
FABRIC:
    ; Read fabric buttons
    MOV DX, FABRIC_PORT
    IN AL, DX

    TEST AL, 08H 
    JZ SET_FABRIC1 

    TEST AL, 10H 
    JZ SET_FABRIC2

    TEST AL, 20H 
    JZ SET_FABRIC3 
    JMP FABRIC 
    
SET_FABRIC1:   
    CALL DELAY20 
    IN AL, DX  
    TEST AL, 08H
    JNZ FABRIC 
    MOV fabric_state, 1
    JMP DIRT   
    
SET_FABRIC2:   
    CALL DELAY20 
    IN AL, DX  
    TEST AL, 10H  
    JNZ FABRIC 
    MOV fabric_state, 2
    JMP DIRT
    
SET_FABRIC3:   
    CALL DELAY20 
    IN AL, DX  
    TEST AL, 20H 
    JNZ FABRIC 
    MOV fabric_state, 3
    JMP DIRT
             
DIRT:         
    ; Read dirtiness buttons
    MOV DX, DIRT_PORT
    IN AL, DX

    TEST AL, 08H 
    JZ SET_DIRT1 

    TEST AL, 10H 
    JZ SET_DIRT2

    TEST AL, 20H 
    JZ SET_DIRT3 

    JMP DIRT
    
SET_DIRT1:   
    CALL DELAY20 
    IN AL, DX  
    TEST AL, 08H
    JNZ DIRT
    MOV dirt_state, 1
    JMP TEND
    
SET_DIRT2:   
    CALL DELAY20 
    IN AL, DX  
    TEST AL, 10H  
    JNZ DIRT 
    MOV dirt_state, 2
    JMP TEND
    
SET_DIRT3:   
    CALL DELAY20 
    IN AL, DX  
    TEST AL, 20H 
    JNZ DIRT 
    MOV dirt_state, 3
    JMP TEND      
    
TEND:   
    POP DX
    POP AX
    RET     
    
READ_INPUTS ENDP

; Check start button
CHECK_START_BUTTON PROC
    PUSH AX
    PUSH DX
    
    MOV DX, CONTROL_PORT
    IN AL, DX
    
    ; Check start button (bit 6)
    TEST AL, 40H
    JNZ CONTROL_END
    MOV start_pressed, 1
    MOV system_running, 1
    
CONTROL_END:
    POP DX
    POP AX
    RET
CHECK_START_BUTTON ENDP

; Main fuzzy inference engine
FUZZY_INFERENCE PROC
    PUSH AX
    PUSH BX
    PUSH CX
    
    ; Clear previous rule strengths
    MOV CX, 10
    MOV BX, OFFSET rule_strength
CLEAR_RULES:
    MOV BYTE PTR [BX], 0
    INC BX
    LOOP CLEAR_RULES
    
    ; Evaluate each rule
    CALL EVAL_RULE_0    ; Small load + light dirt
    CALL EVAL_RULE_1    ; Medium load + medium dirt
    CALL EVAL_RULE_2    ; Large load + heavy dirt
    CALL EVAL_RULE_3    ; Delicate fabric
    CALL EVAL_RULE_4    ; Tough fabric + heavy dirt
    CALL EVAL_RULE_5    ; Hot temp + tough fabric
    CALL EVAL_RULE_6    ; Cold temp + heavy dirt
    CALL EVAL_RULE_7    ; Large load + delicate fabric
    CALL EVAL_RULE_8    ; Light dirt + normal fabric
    CALL EVAL_RULE_9   ; Small load + medium dirt
    
    ; Calculate final outputs using weighted average
    CALL CALCULATE_SPIN_SPEED
    CALL CALCULATE_DURATION
    
    POP CX
    POP BX
    POP AX
    RET
FUZZY_INFERENCE ENDP 

;=================== Evaluating Rules ===================

; Rule 0: Load = small AND Dirt = light ? Spin = Low, Duration = Short
EVAL_RULE_0 PROC
    CMP load_state, 1
    JNE RULE0_END
    CMP dirt_state, 1
    JNE RULE0_END                 
    
    MOV rule_strength[0], 1
RULE0_END:
    RET
EVAL_RULE_0 ENDP

; Rule 1: Load = medium AND Fabric = normal ? Spin = Medium, Duration = Medium
EVAL_RULE_1 PROC
    CMP load_state, 2
    JNE RULE1_END
    CMP fabric_state, 2
    JNE RULE1_END
    
    MOV rule_strength[1], 1
RULE1_END:
    RET
EVAL_RULE_1 ENDP

; Rule 2: Load = large AND Fabric = tough ? Spin = High, Duration = Long
EVAL_RULE_2 PROC
    CMP load_state, 3
    JNE RULE2_END
    CMP fabric_state, 3
    JNE RULE2_END
    
    MOV rule_strength[2], 1
RULE2_END:
    RET
EVAL_RULE_2 ENDP

; Rule 3: Fabric = delicate AND Temp = cold ? Spin = Low
EVAL_RULE_3 PROC
    CMP fabric_state, 1
    JNE RULE3_END
    CMP temp_state, 1
    JNE RULE3_END          
    
    MOV rule_strength[3], 1
RULE3_END:
    RET
EVAL_RULE_3 ENDP

; Rule 4: Fabric = tough AND Temp = hot ? Spin = High
EVAL_RULE_4 PROC
    CMP fabric_state, 3
    JNE RULE4_END
    CMP temp_state, 3
    JNE RULE4_END
    
    MOV rule_strength[4], 1
RULE4_END:
    RET
EVAL_RULE_4 ENDP

; Rule 5: Dirt = heavy AND Temp = warm ? Duration = Long
EVAL_RULE_5 PROC
    CMP dirt_state, 3
    JNE RULE5_END
    CMP temp_state, 2
    JNE RULE5_END
    
    MOV rule_strength[5], 1
RULE5_END:
    RET
EVAL_RULE_5 ENDP

; Rule 6: Dirt = medium AND Load = medium ? Duration = Medium
EVAL_RULE_6 PROC
    CMP dirt_state, 2
    JNE RULE6_END
    CMP load_state, 2
    JNE RULE6_END
    
    MOV rule_strength[6], 1
RULE6_END:
    RET
EVAL_RULE_6 ENDP

; Rule 7: Dirt = light AND Fabric = normal ? Duration = Short
EVAL_RULE_7 PROC
    CMP dirt_state, 1
    JNE RULE7_END
    CMP fabric_state, 2
    JNE RULE7_END
    
    MOV rule_strength[7], 1
RULE7_END:
    RET
EVAL_RULE_7 ENDP

; Rule 8: Load = large AND Temp = cold ? Duration = Long
EVAL_RULE_8 PROC
    CMP load_state, 3
    JNE RULE8_END
    CMP temp_state, 1
    JNE RULE8_END
    
    MOV rule_strength[8], 1
RULE8_END:
    RET
EVAL_RULE_8 ENDP

; Rule 9: Load = small AND Fabric = delicate ? Spin = Low
EVAL_RULE_9 PROC
    CMP load_state, 1
    JNE RULE9_END
    CMP fabric_state, 1
    JNE RULE9_END
    
    MOV rule_strength[9], 1
RULE9_END:
    RET
EVAL_RULE_9 ENDP
                        
CALCULATE_SPIN_SPEED PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH SI

    ; Clear accumulators
    MOV AX, 0
    MOV spin_numerator, AX
    MOV spin_denominator, AX

    ; ----------------------------
    ; Rule 1, 4, 8: Low speed (500 RPM)
    MOV CL, 0
    ADD CL, rule_strength[0]
    ADD CL, rule_strength[3]
    ADD CL, rule_strength[9]

    CMP CL, 0
    JE SKIP_LOW_SPEED

    MOV AL, CL
    MOV AH, 0        
    
    MOV SI, 500
    MUL SI              ; AX = AX(copied from 00CX)(16-bit) * SI(16-bit)(500)     (output is stored in DX:AX but because DX would be 0000 (3 * 500 = 1500(11-bit)), we won't need it)
    ADD spin_numerator, AX
    ADD spin_denominator, CX

SKIP_LOW_SPEED:

    ; ----------------------------
    ; Rule 2, 10: Medium speed (800 RPM)
    MOV CL, 0
    ADD CL, rule_strength[1]

    CMP CL, 0
    JE SKIP_MED_SPEED
    
    MOV AL, CL
    MOV AH, 0      
    
    MOV SI, 800
    MUL SI
    ADD spin_numerator, AX
    ADD spin_denominator, CX

SKIP_MED_SPEED:

    ; ----------------------------
    ; Rule 3, 6: High speed (1100 RPM)
    MOV CL, 0
    ADD CL, rule_strength[2]
    ADD CL, rule_strength[4]

    CMP CL, 0
    JE SKIP_HIGH_SPEED

    MOV AL, CL
    MOV AH, 0      
    
    MOV SI, 1100
    MUL SI
    ADD spin_numerator, AX
    ADD spin_denominator, CX

SKIP_HIGH_SPEED:

    ; ----------------------------
    ; Final division
    MOV AX, spin_denominator
    CMP AX, 0
    JE DEFAULT_SPIN

    MOV BX, AX                ; BX = denominator
    MOV AX, spin_numerator
    DIV BX                 ; AX / BX ---> quotient = AX and remainder = DX
    MOV spin_speed_val, AX
    JMP SPIN_END

DEFAULT_SPIN:
    MOV spin_speed_val, 800   ; Default to medium if no rule fired

SPIN_END:
    POP SI
    POP CX
    POP BX
    POP AX
    RET
CALCULATE_SPIN_SPEED ENDP

; Calculate final duration using weighted average defuzzification
CALCULATE_DURATION PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH SI
    
    ; JMP DEFAULT_DURATION ; DEBUG: for min count down, uncomment
    ; Clear accumulators
    MOV AX, 0
    MOV time_numerator, AX
    MOV time_denominator, AX
    
    ; Rule 1, 9: Short duration (30 minutes = 1800 seconds)
    MOV CL, 0
    ADD CL, rule_strength[7]
    ADD CL, rule_strength[0]

    CMP CL, 0
    JE SKIP_SHORT_DURATION

    MOV AL, CL
    MOV AH, 0        
    
    MOV SI, 1800
    MUL SI              ; AX = AX(copied from CX)(16-bit) * SI(16-bit)(1800 sec)     (output is stored in DX:AX but because DX would be 0000 (2 * 1800 = 3600(12-bit)), we won't need it)
    ADD time_numerator, AX
    ADD time_denominator, CX

SKIP_SHORT_DURATION:
    ; Rule 2: Medium duration (52 minutes = 3120 seconds)
    MOV CL, 0
    ADD CL, rule_strength[6]
    ADD CL, rule_strength[1]

    CMP CL, 0
    JE SKIP_MEDIUM_DURATION

    MOV AL, CL
    MOV AH, 0        
    
    MOV SI, 3120
    MUL SI              ; AX = AX(copied from CX)(16-bit) * SI(16-bit)(3120 sec)     (output is stored in DX:AX but because DX would be 0000 (1 * 3120 = 3120(12-bit)), we won't need it)
    ADD time_numerator, AX
    ADD time_denominator, CX
    
SKIP_MEDIUM_DURATION:
    ; Rule 3, 5, 7: Long duration (75 minutes = 4500 seconds)
    MOV CL, 0
    MOV CL, rule_strength[2]   
    MOV CL, rule_strength[5]   
    ADD CL, rule_strength[8]
                 
    CMP CL, 0
    JE SKIP_LONG_DURATION
    
    MOV AL, CL
    MOV AH, 0        
    
    MOV SI, 4500
    MUL SI              ; AX = AX(copied from CX)(16-bit) * SI(16-bit)(4500 sec)     (output is stored in DX:AX but because DX would be 0000 (3 * 4500 = 13500(14-bit)), we won't need it)
    ADD time_numerator, AX
    ADD time_denominator, CX

SKIP_LONG_DURATION:
    ; ----------------------------
    ; Final division
    MOV AX, time_denominator
    CMP AX, 0
    JE DEFAULT_DURATION

    MOV BX, AX                ; BX = denominator
    MOV AX, time_numerator
    DIV BX                 ; AX / BX ---> quotient = AX and remainder = DX
    MOV duration_val, AX
    JMP DURATION_END

DEFAULT_DURATION:
    ; MOV duration_val, 3120   ; Default to medium if no rule fired
    MOV duration_val, 3600   ; DEBUG


DURATION_END:
    POP SI
    POP CX
    POP BX
    POP AX

    CALL CONVERT_DURATION ; Converting the seconds into h, m, sec

    RET
CALCULATE_DURATION ENDP

;==================== TEMP AND STOP BUTTON CONTROL ====================

CHECK_SYSTEM PROC
    PUSH AX
    
    CMP system_running, 1
    JNE SYSTEM_FINE

    ; Setting stop_pressed to 1 is for more than 10 sec temp_alerted was 1
    CALL CHECK_TEMP
    
    
    CMP temp_alerted, 1
    JNE STOP_BUTTON_CHECKING

    ; Increment time that we had consistent alert by 1
    MOV AL, temp_sec_alert
    INC AL
    MOV temp_sec_alert, AL

    ; If it was consistent for more that 10 seconds, then system will stop and reset
    CMP temp_sec_alert, 10
    JB STOP_BUTTON_CHECKING

    MOV stop_pressed, 1

STOP_BUTTON_CHECKING:
    CALL CHECK_STOP_BUTTON

SYSTEM_FINE:
    
    POP AX
    RET
CHECK_SYSTEM ENDP

CHECK_STOP_BUTTON PROC
    PUSH AX

    IN AL, CONTROL_PORT
    TEST AL, 80H
    JNZ STOP_CONTROL_END
    CALL DELAY_1SEC
    IN AL, CONTROL_PORT
    TEST AL, 80H
    JNZ STOP_CONTROL_END

    MOV stop_pressed, 1

STOP_CONTROL_END:
    POP AX
    RET
CHECK_STOP_BUTTON ENDP

CHECK_TEMP PROC
    PUSH AX
    PUSH DX
    IN AL, MACHINE_TEMP_PORT
    XOR AH, AH

    
    CMP AL, 36  
    JB TEMP_OK         ; If AL < 70, TEMP 

    ; If AL >= 70
    MOV temp_alerted, 1
    CALL TEMP_ALERT_ON
    
    JMP RESTORE_AX      ; Skip calling TEMP_ALERT_OFF

TEMP_OK:
    CALL TEMP_ALERT_OFF
    MOV temp_alerted, 0
    MOV temp_sec_alert, 0

RESTORE_AX:
    POP DX
    POP AX
    RET
CHECK_TEMP ENDP

TEMP_ALERT_ON PROC
    PUSH AX
    
    MOV AL, 00001001b
    OUT LED_BUZZER_PORT, AL

    POP AX
    RET
TEMP_ALERT_ON ENDP

TEMP_ALERT_OFF PROC
    PUSH AX
    
    MOV AL, 00000001b
    OUT LED_BUZZER_PORT, AL

    POP AX
    RET
TEMP_ALERT_OFF ENDP

;==================== TIMER AND LCD ====================

SEND_OUTPUTS PROC
    CALL SEND_TO_LCD
    CALL SEND_TO_TIMER
    MOV stop_pressed, 1

    RET
SEND_OUTPUTS ENDP

SEND_TO_LCD PROC 
;input: none
;output: none
	PUSH AX
	PUSH CX
	PUSH DX
	PUSH SI

	; set segment registers: 
    MOV AX, @DATA
    MOV DS, AX
    MOV ES, AX  
    
    ; define IO ports
    MOV DX, PORT_CONTROL
    MOV AL,10000000B   ; set all ports as output
    OUT DX, AL  
    
    CALL LCD_INIT	

	; ???????? ?? ??? 1 ???? 1
    MOV DL, 1
    MOV DH, 1
    CALL LCD_SET_CUR

    ; ??? ???? "SPIN:"
    LEA SI, SPIN_STR
    CALL LCD_PRINTSTR 
    
    MOV AX, spin_speed_val
    CALL LCD_PRINT_NUM 
    
     LEA SI, RPM_STR
    CALL LCD_PRINTSTR

    ; ???????? ?? ??? 2 ???? 1
    MOV DL, 2
    MOV DH, 1
    CALL LCD_SET_CUR
                        
    LEA SI, TIME_STR
    CALL LCD_PRINTSTR
    
    MOV AX, duration_val
    CALL LCD_PRINT_NUM
    
     LEA SI, S_STR
    CALL LCD_PRINTSTR

    MOV CX, 60000
    CALL DELAY    

	POP SI
	POP DX
	POP CX
	POP AX

	RET
SEND_TO_LCD ENDP 


;=======================================================
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                    ;
;		LCD function library.        ;
;                                    ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DELAY PROC 
;input: CX, this value controls the delay. CX=50 means 1ms
;output: none
	JCXZ @DELAY_END
	@DEL_LOOP:
	LOOP @DEL_LOOP	
	@DELAY_END:
	RET
DELAY ENDP 


; LCD initialization
LCD_INIT PROC 

;make RS=En=RW=0
	MOV AL,0
	CALL OUT_B
;delay 20ms
	MOV CX,1000
	CALL DELAY
;reset sequence
	MOV AH,30H
	CALL LCD_CMD
	MOV CX,250
	CALL DELAY
	
	MOV AH,30H
	CALL LCD_CMD
	MOV CX,50
	CALL DELAY
	
	MOV AH,30H
	CALL LCD_CMD
	MOV CX,500
	CALL DELAY
	
;function set
	MOV AH,38H
	CALL LCD_CMD
	
	MOV AH,0CH
	CALL LCD_CMD
	
	MOV AH,01H
	CALL LCD_CMD
	
	MOV AH,06H
	CALL LCD_CMD
	MOV PORTB_VAL, 00H

	
	RET	
LCD_INIT ENDP 

;sends commands to LCD
LCD_CMD PROC 
    PUSH DX
    PUSH AX

    MOV AL, PORTB_VAL
    AND AL, 3FH     ;  EN(7), RS(6), RW(5)
    CALL OUT_B      

    MOV AL, AH
    CALL OUT_C

    MOV AL, PORTB_VAL
    OR  AL, 80H     
    CALL OUT_B

    MOV CX, 50
    CALL DELAY

    MOV AL, PORTB_VAL
    AND AL, 7FH     
    CALL OUT_B

    MOV CX, 50
    CALL DELAY

    POP AX
    POP DX
    RET
LCD_CMD ENDP 

LCD_CLEAR PROC
	MOV AH,1
	CALL LCD_CMD
	RET	
LCD_CLEAR ENDP

LCD_WRITE_CHAR PROC 
    PUSH AX
    PUSH DX

    ; RS
    MOV AL, PORTB_VAL
    OR AL, 40H     
    CALL OUT_B
    
    MOV AL, AH
    CALL OUT_C

    ; EN
    MOV AL, PORTB_VAL
    OR AL, 80H     
    CALL OUT_B

    MOV CX, 50
    CALL DELAY

    MOV AL, PORTB_VAL
    AND AL, 7FH    
    CALL OUT_B

    POP DX
    POP AX
    RET
LCD_WRITE_CHAR ENDP 

LCD_PRINTSTR PROC 
; input: SI = string address, ends with '$'
; output: none

	PUSH SI
	PUSH AX

@LCD_PRINTSTR_LT:
	LODSB             ; AL ? [SI], SI++
	CMP AL, '$'       
	JE @LCD_PRINTSTR_EXIT

	MOV AH, AL        ; AL ? AH LCD_WRITE_CHAR
	CALL LCD_WRITE_CHAR
	JMP @LCD_PRINTSTR_LT

@LCD_PRINTSTR_EXIT:
	POP AX
	POP SI
	RET
LCD_PRINTSTR ENDP 

;----------------------------
LCD_PRINT_NUM PROC 
	PUSH AX
	PUSH BX
	PUSH CX
	PUSH DX
	PUSH SI

	MOV SI, OFFSET NUM_BUF+5  
	MOV CX, 0                

	MOV BX, 10               

	CMP AX, 0
	JNE @CONVERT

	MOV BYTE PTR [SI], '0'
	DEC SI
	MOV CX, 1
	JMP @DONE_CONVERT

@CONVERT:
	@LOOP_CONVERT:
		XOR DX, DX
		DIV BX            ; AX / 10 => AL=quotient, DX=remainder
		ADD DL, '0'
		MOV [SI], DL
		DEC SI
		INC CX
		TEST AX, AX
		JNZ @LOOP_CONVERT

@DONE_CONVERT:
	MOV BYTE PTR NUM_BUF+5+1, '$'

	LEA SI, [SI+1]
	CALL LCD_PRINTSTR

	POP SI
	POP DX
	POP CX
	POP BX
	POP AX
	RET
LCD_PRINT_NUM ENDP 

;sets the cursor
LCD_SET_CUR PROC 
;input: DL=ROW, DH=COL
;		DL = 1, means upper row
;		DL = 2, means lower row
;		DH = 1-8, 1st column is 1
;output: none


;save registers
	PUSH AX
;LCD uses 0 based column index
	DEC DH
;select case	
	CMP DL,1
	JE	@ROW1
	CMP DL,2
	JE	@ROW2
	JMP @LCD_SET_CUR_END
	
;if DL==1 then
	@ROW1:
		MOV AH,80H
	JMP @LCD_SET_CUR_ENDCASE
	
;if DL==2 then
	@ROW2:
		MOV AH,0C0H
	JMP @LCD_SET_CUR_ENDCASE
		
;execute the command
	@LCD_SET_CUR_ENDCASE:	
	ADD AH,DH
	CALL LCD_CMD
	
;exit from procedure
	@LCD_SET_CUR_END:
	POP AX
	RET
LCD_SET_CUR ENDP 

LCD_SHOW_CUR PROC 
;input: none
;output: none
	PUSH AX
	MOV AH,0FH
	CALL LCD_CMD
	POP AX
	RET
LCD_SHOW_CUR ENDP 


LCD_HIDE_CUR PROC 
;input: none
;output: none
	PUSH AX
	MOV AH,0CH
	CALL LCD_CMD
	POP AX
	RET
LCD_HIDE_CUR ENDP 


OUT_A PROC 
;input: AL
;output: PORTB_VAL	
	PUSH DX
	MOV DX,PORT_A1
	OUT DX,AL
	MOV PORTA_VAL,AL
	POP DX
	RET
OUT_A ENDP 

OUT_B PROC 
;input: AL
;output: PORTB_VAL	
	PUSH DX
	MOV DX,PORT_B1
	OUT DX,AL
	MOV PORTB_VAL,AL
	POP DX
	RET
OUT_B ENDP 

OUT_C PROC 
;input: AL
;output: PORTC_VAL	
	PUSH DX
	MOV DX,PORT_C1
	OUT DX,AL
	MOV PORTC_VAL,AL
	POP DX
	RET
OUT_C ENDP 

;====================================================== TIMER ======================================================

SEND_TO_TIMER PROC

TIMER_LOOP:
    ; If stop button is pressed for some ms or high temp stays more that 10 seconds, we will exit and halt.
    CALL CHECK_SYSTEM
    CMP stop_pressed, 1
    JE EXIT_PROGRAM

    CALL UPDATE_DISPLAY
    
    ; If time calculated is 0, then just exit and don't count a sec.
    ;This happens when you the first countdown is completed and we call system_reset and we want to reset the seven segs too.\
    CMP duration_val, 0
    JE EXIT_PROGRAM 

    CALL DELAY_1SEC
    CALL DECREMENT_TIME

    CMP duration_hr, 0
    JNE TIMER_LOOP
    CMP duration_min, 0
    JNE TIMER_LOOP
    CMP duration_sec, 0
    JNE TIMER_LOOP

    JMP EXIT_PROGRAM

EXIT_PROGRAM:
    RET
SEND_TO_TIMER ENDP

UPDATE_DISPLAY PROC
    PUSH AX
    PUSH BX
    PUSH CX 
    PUSH DX 
    PUSH SI

    ; ===== Display HOURS =====
    MOV   AL, duration_hr
    XOR   AH, AH         ; <� clear AH before dividing
    MOV   BL, 10
    DIV   BL             ; AL = tens, AH = units

    MOV   SI, OFFSET SEG_TABLE
    MOV   BL, AL         ; tens digit
    MOV   BH, 0
    ADD   SI, BX
    MOV   AL, [SI]
    OUT   PORTA3, AL        ; Hours tens

    MOV   BL, AH         ; units digit
    MOV   BH, 0
    MOV   SI, OFFSET SEG_TABLE
    ADD   SI, BX
    MOV   AL, [SI]
    OUT   PORTB3, AL        ; Hours units

    ; ===== Display MINUTES =====
    MOV   AL, duration_min
    XOR   AH, AH         ; <� clear before DIV
    MOV   BL, 10
    DIV   BL             ; AL = tens, AH = units

    MOV   SI, OFFSET SEG_TABLE
    MOV   BL, AL         ; minutes-tens
    MOV   BH, 0
    ADD   SI, BX
    MOV   AL, [SI]
    OUT   PORTC3, AL        ; Minutes tens

    MOV   BL, AH         ; minutes-units
    MOV   BH, 0
    MOV   SI, OFFSET SEG_TABLE
    ADD   SI, BX
    MOV   AL, [SI]
    OUT   PORTA4, AL        ; Minutes units

    ; ===== Display SECONDS =====
    MOV   AL, duration_sec
    XOR   AH, AH         ; <� clear before DIV
    MOV   BL, 10
    DIV   BL             ; AL = tens, AH = units

    MOV   SI, OFFSET SEG_TABLE
    MOV   BL, AL         ; seconds-tens
    MOV   BH, 0
    ADD   SI, BX
    MOV   AL, [SI]
    OUT   PORTC4, AL        ; Seconds tens

    MOV   BL, AH         ; seconds-units
    MOV   BH, 0
    MOV   SI, OFFSET SEG_TABLE
    ADD   SI, BX
    MOV   AL, [SI]
    OUT   PORTB4, AL        ; Seconds units


    POP SI 
    pop DX
    pop CX
    pop BX
    pop AX
    RET
UPDATE_DISPLAY ENDP

DECREMENT_TIME PROC
    PUSH AX
    DEC duration_sec
    CMP duration_sec, 0FFH
    JNE DONE
    MOV duration_sec, 59
    DEC duration_min
    CMP duration_min, 0FFH
    JNE DONE
    MOV duration_min, 59
    DEC duration_hr
    CMP duration_hr, 0FFH
    JNE DONE
    MOV duration_hr, 0
DONE:
    POP AX
    RET
DECREMENT_TIME ENDP

DELAY_1SEC PROC
    PUSH CX
    MOV CX, 200
DELAY_LOOP:
    CALL DELAY_1MS
    LOOP DELAY_LOOP
    POP CX
    RET
DELAY_1SEC ENDP

; 1 ms delay (roughly)
DELAY_1MS PROC
    PUSH CX
    MOV CX, 1000
DELAY1MS_LOOP:
    NOP
    LOOP DELAY1MS_LOOP
    POP CX
    RET
DELAY_1MS ENDP



; _________ Reset all outputs and memory vars when system stops _________
RESET_OUTPUTS PROC
    ; Status flags restarted
    MOV system_running, 0
    MOV stop_pressed, 0

    MOV temp_alerted, 0
    MOV temp_sec_alert, 0

    ; Saved values cleared
    MOV spin_speed_val, 0
    MOV duration_val, 0

    MOV duration_hr, 0
    MOV duration_min, 0
    MOV duration_sec, 0

    ; CALL SEND_TO_LCD 
    ;Setting 7segs to 00:00:00
    CALL SEND_TO_TIMER

    ; CLEARING RULE BASE
    PUSH DI
    PUSH CX

    MOV CX, 10
    LEA DI, rule_strength
    
CLEAR_ARRAY_LOOP:
    MOV BYTE PTR [DI], 0
    INC DI
    LOOP CLEAR_ARRAY_LOOP

    POP CX
    POP DI

    
    RET
RESET_OUTPUTS ENDP

;A proc that causes delay
DELAY20 PROC
    PUSH CX
    PUSH DX

    MOV CX, 1000      ; Outer loop
DELAY20_OUTER:
    MOV DX, 100       ; Inner loop
DELAY20_INNER:
    NOP               ; No operation, wastes 1 cycle
    DEC DX
    JNZ DELAY20_INNER

    LOOP DELAY20_OUTER

    POP DX
    POP CX
    RET
DELAY20 ENDP

CONVERT_DURATION PROC
    PUSH AX
    PUSH BX
    PUSH DX

    ; Load duration_val (in seconds)
    MOV AX, duration_val

    ; Compute hours: AX / 3600
    MOV BX, 3600
    XOR DX, DX
    DIV BX                ; AX / 3600 ? AX = hours, DX = remainder
    MOV duration_hr, AL   ; store hours
    MOV AX, DX            ; remainder seconds

    ; Compute minutes: AX / 60
    MOV BX, 60
    XOR DX, DX
    DIV BX                ; AX / 60 ? AX = minutes, DX = seconds
    MOV duration_min, AL  ; store minutes
    MOV duration_sec, DL  ; store seconds

    POP DX
    POP BX
    POP AX
    RET
CONVERT_DURATION ENDP

END MAIN