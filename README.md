## features

creates four logfiles in `sourcemod/logs/frametime`  
- log 1. logs engine time differences per tick, every tick
- log 2. logs engine time difference averages and standard deviation over 10 ticks
- log 3. same as log 2 but 100 ticks
- log 4. same as log 2 but 1000 ticks

note: ignore the first value of each logfile. first one is mega skewed

## usage

- `sm_framelog "prefix" <tickcount>`
- `prefix` is the prefix to include in the logfile names
- `tickcount` is for how many ticks you want to log (min: 1, max: 9999)

## cvars

generated in `sourcemod/configs/frametime_deviation.cfg`

```// Enable frame time deviation logging for 1000 ticks
// -
// Default: "1"
sm_frametime_enable_1000_ticks "1"

// Enable frame time deviation logging for 100 ticks
// -
// Default: "1"
sm_frametime_enable_100_ticks "1"

// Enable frame time deviation logging for 10 ticks
// -
// Default: "1"
sm_frametime_enable_10_ticks "1"

// Enable frame time per tick logging
// -
// Default: "1"
sm_frametime_enable_per_tick "1"
```
