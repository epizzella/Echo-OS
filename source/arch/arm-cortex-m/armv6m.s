/*
 Copyright 2024 Edward Pizzella
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

.extern  current_task
.extern  next_task
.extern  g_stack_offset
.global PendSV_Handler
.thumb_func

PendSV_Handler:
    CPSID   I
    LDR     R3, =g_stack_offset
    LDR     R3, [R3] 
    LDR     R0, =current_task
    LDR     R1, [R0]                     
    CMP     R1, #0                      /* If current_task is null skip context save */
    BEQ     ContextRestore

    MRS     R2, PSP                     /* Move process stack pointer into R2 */
    SUBS    R2, R2, #0x20               /* Adjust stack point for R8-R11  */

    STR     R2, [R1, R3]                /* Save the current stack pointer in current_task */

    STMIA   R2!, {R4-R7}                /* Push registers R4-R7 on the stack */

    MOV     R4, R8                      /* Push registers R8-R11 on the stack */
    MOV     R5, R9
    MOV     R6, R10
    MOV     R7, R11
    STMIA   R2!, {R4-R7}

ContextRestore:
    LDR     R1, =next_task          
    LDR     R1, [R1]                                             
    LDR     R2, [R1, R3]                /* Set stack pointer to next_task stack pointer */

    ADDS    R2, R2, #0x10               /* Adjust stack pointer */
    LDMIA   R2!, {R4-R7}                /* Pop registers R8-R11 */  
    MOV     R8,  R4                                                                
    MOV     R9,  R5
    MOV     R10, R6
    MOV     R11, R7  

    MSR     PSP, R2                     /* Load PSP with final stack pointer */

    SUBS    R2, R2, #0x20               /* Adjust stack pointer */
    LDMIA   R2!, {R4-R7}                /* Pop register R4-R7 */

    STR     R1, [R0, #0x00]             /* Set current_task to next_task */

    MOVS    R3, 0x02                    /* Load EXC_RETURN with 0xFFFFFFFD*/
    MVNS    R3, R3
    MOV     LR, R3

    CPSIE   I                         
    BX      LR
.size PendSV_Handler, .-PendSV_Handler
