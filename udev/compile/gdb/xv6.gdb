# Stop hook from xv6-public/.gdbinit.tmpl.
# Kernel CS is 8. User CS is 35. Anything else is the 16-bit bootloader.
set $lastcs = -1

define hook-stop
  if $cs == 8 || $cs == 35
    if $lastcs != 8 && $lastcs != 35
      set architecture i386
    end
    x/i $pc
  else
    if $lastcs == -1 || $lastcs == 8 || $lastcs == 35
      set architecture i8086
    end
    printf "[%4x:%4x] ", $cs, $eip
    x/i $cs*16+$eip
  end
  set $lastcs = $cs
end

define xv6-where
  printf "cs=%d eip=%p\n", $cs, $eip
  bt
end
