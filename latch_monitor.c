#include <errno.h>
#include <stdio.h>
#include <numaif.h>
#include <sys/shm.h>



int main(int argc, char **argv )
{
        char *address;
        char *latch_state;
        char *ultralatch_state;
        char buf[17];
        char latch_free[]="0000000000000000";
        void *addr;
        int i;
        int j;
        int add_print=0;
        int flg3;
        int process_count;
        int shmid;

        printf("Enter min process addr : ");
        scanf("%p", &address);
        printf("Enter nb process : ");
        scanf("%d", &process_count);
        printf("Enter shmid :");
        scanf("%d", &shmid);

        addr =shmat(shmid,(void *) 0x0000006b000000 ,SHM_RDONLY);

        if(addr == (void *)-1) {
           perror("shmop: shmat failed");
        }

		//Loop throught x$ksupr
		for(i=0;i<process_count;i++)
		{
				//4240 is x$ksupr entry size
				address = address + 4240;

				//check if the slot is active using KSUPRFLG3
				flg3 = address[180];

				if(flg3 != 0 )  {		  

				 //First element of the latch state object array
				 latch_state=address + 568;
				 add_print=0;
				 for (j=1;j<19;j++) {						 
						   unsigned char *p = (unsigned  char *)latch_state;
						   snprintf(buf, sizeof buf, "%02x%02x%02x%02x%02x%02x%02x%02x",  p[7], p[6], p[5], p[4], p[3], p[2], p[1], p[0]);
						   if ( strcmp(buf,latch_free) != 0) {
						   if (add_print == 0 ){
										printf("Process address %p pid %d\n",address,i+1);
										add_print=1;
								}
								printf("Holding latch at address %s\n",buf);
						   }

						   latch_state=latch_state +16;
						}
				//Ultra fast latch state object address
				 ultralatch_state = address + 1448;
				 unsigned char *p2 = (unsigned  char *)ultralatch_state;
				 snprintf(buf, sizeof buf, "%02x%02x%02x%02x%02x%02x%02x%02x",  p2[7], p2[6], p2[5], p2[4], p2[3], p2[2], p2[1], p2[0]);
				 if ( strcmp(buf,latch_free) != 0) {
						   if (add_print == 0 ){
										printf("Process address %p pid %d\n",address,i+1);
										add_print=1;
								}
								printf("Holding ultra fast latch at address %s\n",buf);
				 }
				}
		}

        return 0;
}

