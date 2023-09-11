% An example:
% This script will use the DMX USB Pro to send a sinusoidal pattern of
% intensities to a single DMX channel. I connected the widget to a waveform
% lighting dimmer, which was connected to a white (single channel) LED
% strip.
% 
% This code generates periods of flickering light with breaks (no light) in
% between.
%
% Most of this code just sets up timers to send new signals The actual communication 
% with the widget is in setIntensity.
%
% BK Sept, 2023.

prt             = "COM3"; % The  port connected to the Enttec DMX USB PRO
                            % If you don't know which one use serialportlist
flickerStartTime    = "14:59"; % When to start (24 hour clock - HH:mm)
frequency       = 2;       % Flicker Frequency (Hz)
amplitude       = 127;      % Flicker amplitude (0-127)
channel         = 1;        % Which channel on teh Waveform Lighting 3082 Dimmer.

flickerDuration = 5;  % How long is flicker deliverd (seconds)
breakDuration = 3;    % How long is the break (no flicker) between flicker bouts (seconds)
nrFlickerPeriods =5;  % How many Flicker periods (number)

%% Connect to the DMX Widget
if ~exist("o","var") || o.port=="NOT CONNECTED"
    o = dmxUsbPro(prt);
    o.outputRate = 40; % Set to maximum
end
%% Setup a timer to start Flicker delivery
% This will fire nrFlickerPeriods times.
startTime = datetime(flickerStartTime,'InputFormat','HH:mm');
t = timer('Name','Session');
t.TimerFcn = @(~,~) flicker(o,channel,amplitude,frequency,flickerDuration);
t.ExecutionMode ="fixedDelay";
t.Period = flickerDuration +breakDuration;
t.StartDelay = 5;
t.TasksToExecute = nrFlickerPeriods;
t.StopFcn   = @(tmr,e) stopCallback(tmr,e);
if startTime < datetime("now")
    start(t);
else
    startat(t,startTime)
end
function stopCallback(~,~)
    fprintf('Last flicker delivery started at %s\n',string(datetime("now")))
end



function flicker(o,channel,amplitude,frequency,duration)
% Each timer above starts one of these timers, which will send updated
% intensity values to the DMX widget at the outputRate of the widget.
startTime = datetime("now");
t = timer('Name',"Flicker" + string(startTime));
t.TimerFcn = @(~,~) setIntensity(o,channel,amplitude,frequency,startTime);
t.ExecutionMode ="fixedDelay";
t.Period = 1./o.outputRate;
t.StartDelay = 0;
t.TasksToExecute = duration*o.outputRate;
t.StopFcn = @(tmr,e) flickerStopCallback(tmr,e,o,channel);
fprintf('Starting Flicker (Ch #%d, Amp: %d @%.2f Hz) for %.2f s (%d updates) @ %s\n',channel,amplitude,frequency,duration,t.TasksToExecute,string(datetime("now","Format","HH:mm:ss.SSS")))
start(t)
end

function flickerStopCallback(tmr,e,o,channel)
    % Turn off the light at the end.
    setChannel(o,channel,0);
    stopDmxOut(o);
    fprintf('%s stopped after delivering %d intensities at an average rate of  %.2f Hz \n\n',tmr.Name,tmr.TasksExecuted,1./tmr.AveragePeriod)
end

function setIntensity(o,channel,amplitude,frequency,startTime)
    % This is called at outputRate and sets the new intensity
    % value on the widget.
    t= datetime("now","Format","hh:mm");
    intensity = (amplitude/2)*(1+sin(seconds(t-startTime)*2*pi*frequency));
    setChannel(o,channel,intensity);
end
