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
    CPSID       I    
    LDR         R2,    =g_stack_offset
    LDR         R2,    [R2]                                  
    LDR         R0,    =current_task
    LDR         R1,    [R0]                     
    CMP         R1,    #0                   /* If current_task is null skip context save */
    BEQ         ContextRestore 
    MRS         R12,   PSP                  /* Move process stack pointer into R12 */

    TST         LR, #0x10                   /* If task was using FPU push FPU registers */                    
    IT          EQ
    VSTMDBEQ    R12!,{S16-S31}

    STMDB       R12!, {R4-R11, LR}          /* Push registers R4-R11 & LR on the stack */
    STR         R12,  [R1, R2]              /* Save the current stack pointer in current_task */
ContextRestore:
    LDR         R3,    =next_task          
    LDR         R3,    [R3]                                            
    LDR         R12,   [R3, R2]             /* Set stack pointer to next_task stack pointer */
    LDMIA       R12!, {R4-R11, LR}          /* Pop registers R4-R11 & LR */

    TST         LR, #0x10                   /* If task was using FPU pop FPU registers */                                      
    IT          EQ
    VLDMIAEQ    R12!,{S16-S31} 

    MSR         PSP, R12                    /* Load PSP with new stack pointer */
    STR         R3, [R0, #0x00]             /* Set current_task to next_task */
    CPSIE       I
    BX          LR
.size PendSV_Handler, .-PendSV_Handler