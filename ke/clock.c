
/*-------------------------------------------------------------
    时钟相关
    
    修改时间列表:
    2011-01-20 21:53:30 
-------------------------------------------------------------*/


#include    "ke.h"
#include    "proto.h"


/*-------------------------------------------------------------
-------------------------------------------------------------*/
/*-----------------------------------------------------------*/



/*-------------------------------------------------------------
    时钟初始化
-------------------------------------------------------------*/

void
_stdcall
HalInitClock()
{
    //
    // 初始化8253芯片,设置时钟中断的频率
    //
    
    HalWritePortChar(PORT_8253_MODE, 0x34);
    HalWritePortChar(PORT_8253_COUNTER0, (uchar)(TIMER_FREQUENCY / OLIEX_HZ));
    HalWritePortChar(PORT_8253_COUNTER0, (uchar)((TIMER_FREQUENCY / OLIEX_HZ) >> 8));
    
    //
    // 连接时钟中断到IDT上,并打开时钟中断,暂没有额外的线程进行后续的处理
    //
    
    KeConnectInterrupt(IRQ0_CLOCK, HalIrq0ClockService, 0);
    
    HalEnableIrq(IRQ0_CLOCK);
}
/*-----------------------------------------------------------*/



/*-------------------------------------------------------------
    硬件时钟中断
-------------------------------------------------------------*/

void
_stdcall
HalIrq0ClockService(
    PKINTERRUPT     Interrupt
    )
{
    PKTHREAD    Thread;
    
    KiSystemTicks++;
    
    Thread = PsCurrentThread;
    Thread->Ticks--;
    
    if ((Thread->Ticks > 0) && (Thread->Flags == 0))
        return;
    
    PsSchedule();
}
/*-----------------------------------------------------------*/















