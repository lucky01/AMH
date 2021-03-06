CON
  clockMillions = 104_000_000
  clockThousands = 104_000

  'clockMillions = 80_000_000
  'clockThousands = 80_000
  
  bufferSize = 1024
  samplesPerBuffer = bufferSize / 8

  numChannels = 4
  
VAR
  long sampleRate
  long numberOfSamples[numChannels]
  word leftVolume[numChannels], rightVolume[numChannels]
  byte triggerStart[numChannels] 
  byte stoppedOrStarted[numChannels]

PUB DACEngineStart(buffer_address, leftPinNumber, rightPinNumber, newRate, whichCog) 

  sampleRate := (clkfreq / ((newRate <# (clkfreq / constant(clockMillions / clockThousands))) #> 1)) 

  'changeSampleRate(newRate)  

  result := ((leftPinNumber <# 31) #> 0)
  newRate := ((rightPinNumber <# 31) #> 0)
  outputMask := (((leftPinNumber <> -1) & (|<result)) | ((rightPinNumber <> -1) & (|<newRate)))  
  leftCounterSetup := (result + constant(%00110 << 26))
  rightCounterSetup := (newRate + constant(%00110 << 26))

  numberSamplesAddress := @numberOfSamples[0]

  dataBlockAddress := buffer_address

  leftVolumeAddress := @leftVolume[0]
  rightVolumeAddress := @rightVolume[0]
  triggerStartAddress := @triggerStart[0]
  stoppedOrStartedAddress := @stoppedOrStarted[0]

  coginit(whichCog, @initialDAC, @sampleRate)                                                           'Start cog


PUB startPlayer(channel, samplesToPlay)   'Starts the player, with offset so it doesn't play the WAV data at the beginning of the file

  ' make sure channel is in range
  if (channel > (numChannels-1) OR channel < 0)
    return
    
  numberOfSamples[channel] := samplesToPlay
  triggerStart[channel] := true

PUB stopPlayer(channel)

  ' make sure channel is in range
  if (channel > (numChannels-1) OR channel < 0)
    return
    
  stoppedOrStarted[channel] := false

PUB Volume(channel, lVol, rVol)

  ' make sure channel is in range
  if (channel > (numChannels-1) OR channel < 0)
    return
    
  leftVolume[channel] := (((lVol <# 100) #> 0) * constant(65536 / 100))
  rightVolume[channel] := (((rVol <# 100) #> 0) * constant(65536 / 100))

PUB IsPlaying(channel)
  if stoppedOrStarted[channel] <> 0
    return 1
  else
    return 0
    

PUB getActiveChannels | g, count

  count := 0

  repeat g from 0 to 2                                  'We don't count 3 as it's assumed music is always plauing

    if stoppedOrStarted[g]

      count += 1

  return count




DAT

                        org 0

' //////////////////////Initialization/////////////////////////////////////////////////////////////////////////////////////////
initialDAC
                        mov     ctra,           leftCounterSetup                ' Setup counter modes to duty cycle mode.
                        mov     ctrb,           rightCounterSetup               '
                        mov     frqa,           longAdjust                      ' 
                        mov     frqb,           longAdjust                      '                         
                        
                        mov     dira,           outputMask                      ' Setup I/O pin directions.

                        ' init all the pointers and stuff
                        mov     tempReg3,       #0                              ' setup stuff to first channel
                        movd    initPtrWrite,   #playerPointer                  '
                        movd    initPtrAdd,     #playerPointer                  '
                        movd    numSamplesClear,#numberSamples                  '
                        movd    bufferPageClear,#bufferPage                     '
                                           
                        mov     currChannel,    #numChannels                    ' loop over channels
initBufferPointersLoop                                                          '
initPtrWrite            mov     0,              dataBlockAddress                ' load base buffer address
initPtrAdd              add     0,              tempReg3                        ' adjust to channels buffer start
numSamplesClear         mov     0,              #0                              ' clear num samples 
bufferPageClear         mov     0,              #0                              ' clear buffer page 

                        add     initPtrWrite,   incDestField                    ' adjust stuff to next channel
                        add     initPtrAdd,     incDestField                    '
                        add     numSamplesClear,incDestField                    '
                        add     bufferPageClear,incDestField                    '
                        add     tempReg3,       channelBufferSize               '
                        
                        djnz    currChannel,    #initBufferPointersLoop       

                        rdlong  timeCounter,     par                            ' Setup timing.  
                        add     timeCounter,     cnt  
     
' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////  
'                       Player
' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

outerLoop
                        mov     counterDAC,     #samplesPerBuffer               ' Number of samples per buffer 


' //////////////////////Inner Loop/////////////////////////////////////////////////////////////////////////////////////////////                               

innerLoop
                        rdlong  tempReg,        par                             ' Wait until next sample output period.
                        waitcnt timeCounter,    tempReg

                        mov     sampleResult,   #0                              ' start with silence
                        mov     currChannel,    #numChannels                    ' Loop over channels for left side
                        movs    multiplicand,   #leftVolumeAddress              ' Set left volume multplicand
                        movs    bufferRead,     #playerPointer
                        movs    bufferWrite,    #playerPointer
                        movd    bufferIncrement,#playerPointer
channelLoopL
                        rdbyte  tempReg,        stoppedOrStartedAddress wz      ' If channel stopped, skip to next channel
if_z                    jmp     #nextChannelL
                        call    #decode                                         ' decode one channel
                        adds    sampleResult,   sampleBuffer                    ' add this channel to the result
nextChannelL                        
                        add     bufferRead,     #1                              ' adjust pointers to next channel
                        add     bufferWrite,    #1                              '
                        add     bufferIncrement,incDestField                    '                        
                        add     stoppedOrStartedAddress, #1                     '
                        add     leftVolumeAddress, #2                           '
                        djnz    currChannel,    #channelLoopL                   ' channel loop left side

                        add     sampleResult,   longAdjust                      ' Center output value.
                        mov     frqa,           sampleResult                    ' write out left side result
                        
                        sub     stoppedOrStartedAddress, #numChannels           ' fix address back to first channel
                        sub     leftVolumeAddress, #numChannels
                        sub     leftVolumeAddress, #numChannels
                        
                        mov     sampleResult,   #0                              ' start with silence
                        mov     currChannel,    #numChannels                    ' Loop over channels for right side
                        movs    multiplicand,   #rightVolumeAddress             ' Set right volume multplicand
                        movs    bufferRead,     #playerPointer
                        movs    bufferWrite,    #playerPointer
                        movd    bufferIncrement,#playerPointer
channelLoopR                                                                     
                        rdbyte  tempReg,        stoppedOrStartedAddress wz      ' If channel stopped, skip to next channel
if_z                    jmp     #nextChannelR
                        call    #decode                                         ' decode one channel
                        adds    sampleResult,   sampleBuffer                    ' add this channel to the result
nextChannelR
                        cmp     tempReg,        #0 wz                           ' test if channel is already stopped
numSamplesSub
if_nz                   sub     numberSamples,  #1 wz                           ' if not stopped, dec sample counter for this channel
if_z                    wrbyte  zero,           stoppedOrStartedAddress         ' If we're out of samples, stop channel

                        add     bufferRead,     #1                              ' adjust pointers to next channel
                        add     bufferWrite,    #1                              '
                        add     bufferIncrement,incDestField                    '                        
                        add     stoppedOrStartedAddress, #1                     '
                        add     rightVolumeAddress, #2                          '
                        add     numSamplesSub,  incDestField                    '
                        djnz    currChannel,    #channelLoopR                   ' channel loop right side
                        
                        add     sampleResult,   longAdjust                      ' Center output value.
                        mov     frqb,           sampleResult                    ' write out right side result

                        sub     stoppedOrStartedAddress, #numChannels           ' fix addresses back to first channel
                        sub     rightVolumeAddress, #numChannels
                        sub     rightVolumeAddress, #numChannels
                        sub     numSamplesSub,  incDestFieldxChannels           '
                                                                                
nextLoop                djnz    counterDAC,     #innerLoop                      ' Sample Loop.

' //////////////////////Outer Loop/////////////////////////////////////////////////////////////////////////////////////////////

                        movd    pageUpdateAdd,  #bufferPage
                        movd    pageUpdateTest, #bufferPage
                        movd    pageUpdateMov,  #bufferPage
                                                                        
                        mov     currChannel,    #numChannels                    ' update bufferPage for each channel
bufferPageUpdateLoop                                                            '
                        rdbyte  tempReg,        stoppedOrStartedAddress wz      ' see if the channel is stopped
if_z                    jmp     #pageUpdateMov                                  ' skip to clearing bufferPage for stopped channel
pageUpdateAdd           add     0,              #1                              ' toggle bufferPage between 0 and 1
pageUpdateTest          cmp     0,              #2 wz                           '
pageUpdateMov                                                                   '
if_z                    mov     0,              #0                              '
                        add     stoppedOrStartedAddress, #1                     '
                        add     pageUpdateAdd,  incDestField                    '
                        add     pageUpdateTest, incDestField                    '
                        add     pageUpdateMov,  incDestField                    '                            
                        djnz    currChannel,    #bufferPageUpdateLoop           '

                        sub     stoppedOrStartedAddress, #numChannels           ' fix addresses back to first channel

                        call    #updatePlayerPtrs
                        jmp     #outerLoop

' //////////////////////Update Player Pointers/////////////////////////////////////////////////////////////////////////////////

updatePlayerPtrs
                        mov     tempReg3,       #0                              ' setup stuff to first channel

                        movd    pointerWrite,   #playerPointer
                        movd    pointerAdd,     #playerPointer
                        movd    pointerAdd2,    #playerPointer
                        movd    numSamplesRead, #numberSamples
                        movd    bufferPageTest, #bufferPage
                                           
                        mov     currChannel,    #numChannels                    ' loop over channels, updating playerPoiners
updateBufferPointersLoop                                                        ' based on bufferPage
                        rdbyte  tempReg,        triggerStartAddress wz          ' see if start trigger is on
if_nz                   wrbyte  one, stoppedOrStartedAddress                    ' if so, set stoppedOrStarted flag on
                        wrbyte  zero, triggerStartAddress                       ' clear the trigger flag
                        rdbyte  tempReg,        stoppedOrStartedAddress wz      ' see if the channel is stopped
if_z                    jmp     #nextChannel                                    ' skip updating pointer for this channel
bufferPageTest          cmp     0,              #0 wz                           ' read what buffer page this channel is on
if_z                    mov     tempReg2,       #0                              ' and set tempReg2 accordingly
if_nz                   mov     tempReg2,       halfChannelBufferSize           '                 

pointerWrite            mov     0,              dataBlockAddress                '
pointerAdd              add     0,              tempReg3                        ' adjust to channels buffer set
pointerAdd2             add     0,              tempReg2                        ' adjust to page within buffer set
numSamplesRead          rdlong  0,              numberSamplesAddress            ' Get current number of samples
nextChannel
                        add     bufferPageTest, incDestField                    ' adjust stuff to next channel
                        add     pointerWrite,   incDestField                    '
                        add     pointerAdd,     incDestField                    '
                        add     pointerAdd2,    incDestField                    '
                        add     numSamplesRead, incDestField                    '
                        add     tempReg3,       channelBufferSize               '
                        add     numberSamplesAddress, #4                        ' 
                        add     stoppedOrStartedAddress, #1                     '
                        add     triggerStartAddress, #1                         '
                        
                        djnz    currChannel,    #updateBufferPointersLoop       

                        sub     numberSamplesAddress, numChannelsx4             ' set stuff back to first channel
                        sub     stoppedOrStartedAddress, #numChannels           '
                        sub     triggerStartAddress, #numChannels               '

                        ' when we exit, everything is left pointing at the first channel

updatePlayerPtrs_ret    ret

' ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////// 
'                       Decode Value
' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

decode                            '
bufferRead              rdword  multiplyBuffer, 0                               ' read the buffer
                        shl     multiplyBuffer, #16                             ' Sign extend.
                        sar     multiplyBuffer, #16                             '
bufferWrite             wrword  zero,           0                               ' clear the buffer
bufferIncrement         add     0,              #2                              ' add 2 to the playerPointer (sample is 2 bytes)
                 
                        cmp     zero,           zero wz

multiplicand            rdword  multiplyCounter,0                               ' Setup inputs.
                        mov     sampleBuffer,   #0                              '
                        abs     multiplyBuffer, multiplyBuffer wc               ' Backup sign.
                        rcr     sampleBuffer,   #1 wz, nr                       '

multiplyLoop            shr     multiplyCounter,#1 wc                           ' Preform multiplication. loops 12-15 times
if_c                    add     sampleBuffer,   multiplyBuffer                  '  
                        shl     multiplyBuffer, #1 wc                           '  
                        tjnz    multiplyCounter,#multiplyLoop                   ' 

                        negnz   sampleBuffer,   sampleBuffer                    ' Restore sign.   
                        
decode_ret              ret

' ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////// 
'                       Data
' ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////// 

wordAdjust              long    $8000                                           ' Edits word signed value.
longAdjust              long    $80000000                                       ' Edits long unsigend value.
incDestField            long    $00000200                                       ' value to add to a reg to inc the dest field in it
incDestFieldxChannels   long    $00000200 * numChannels
zero                    long    0
one                     long    1

' //////////////////////Configuration Settings/////////////////////////////////////////////////////////////////////////////////

leftCounterSetup        long    0
rightCounterSetup       long    0
outputMask              long    0
channelBufferSize       long    bufferSize
halfChannelBufferSize   long    bufferSize / 2
numChannelsx4           long    numChannels * 4  

' //////////////////////Addresses//////////////////////////////////////////////////////////////////////////////////////////////

numberSamplesAddress    long    0
dataBlockAddress        long    0
sampleRateAddress       long    0
leftVolumeAddress       long    0
rightVolumeAddress      long    0
triggerStartAddress     long    0
stoppedOrStartedAddress long    0

' //////////////////////Run Time Variables/////////////////////////////////////////////////////////////////////////////////////

numberSamples           res     numChannels
playerPointer           res     numChannels
bufferPage              res     numChannels
counterDAC              res     1
currChannel             res     1
sampleBuffer            res     1
sampleResult            res     1
timeCounter             res     1
multiplyBuffer          res     1
multiplyCounter         res     1

tempReg                 res     1
tempReg2                res     1
tempReg3                res     1

' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

                        fit     496

                        