/* Static guest program.
 * Edit, then from compile/: ./experiment.sh build probe
 */
#include <stdio.h>
#include <sys/utsname.h>

int main(void)
{
	struct utsname u;
	char release[128];
	FILE *f;

	if (uname(&u) != 0)
		return 1;
	printf("sysname=%s\nrelease=%s\nversion=%s\n",
	       u.sysname, u.release, u.version);

	f = fopen("/proc/sys/kernel/osrelease", "r");
	if (!f)
		return 1;
	if (!fgets(release, sizeof release, f))
		return 1;
	fclose(f);
	printf("osrelease=%s", release);
	return 0;
}
