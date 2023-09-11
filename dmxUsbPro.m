classdef dmxUsbPro <handle
    % A class to communicate with Enttec's DMX USB Pro widget. With this
    % widget you can control devices that use the DMX512 protocol (e.g,
    % dimmers, lighting, fog machines, a complete rock opera) from Matlab
    % running on a Windows machine. 
    %
    % For this to work, you first install Enttec's EMU or the older (but simpler) 
    % Pro-Manager from here: https://support.enttec.com/support/solutions/articles/101000394255-usb-dmx-compatible-usb-software
    % The main reason to install these is to get the FTDI drivers for the USB 
    % device on your machine and then to confirm they are working by
    % connecting to the device from these apps. 
    %     
    % Either of these apps, or the windows device manager, will tell you
    % which COM port the DMX USB PRO device is connected to. On my machine
    % that was COM3 , so the default setting below is COM3, but you can use
    % any COM port when constructing an object of this class. 
    %
    % 
    % PreRequisites:
    %  FTDI Drivers installed (simplest via EntTec Pro-Manager)
    %  Matlab R2019b or later (to use the serialport class)
    %
    %% EXAMPLE
    %   o = dmxUsbPro("COM3"); % Construct an object
    %   o.outputRate =40; % Updating the DMX output signal at 40 Hz. (max)
    %   o.breakTime = 20; % Set the break time of the DMX protocol to 20*10.67 microseconds
    %  o.markAfterBreakTime = 2; % Set the mark after break time to 2 *10.67 mus.
    %% Inspect the object  to see the parameters;
    %  o 
    %% Send out a DMX message to your fixture:
    % For instance, to send startCode 0 and the value 128 to all 512
    % channels in the DMX universe: 
    % startDmxOut(o,0,128*ones(1,512))
    % This message will be sent every 1/outputRate seconds (the blinking light on the widget indicates this)
    % until you call
    % stopDmxOut(o)
    %
    % I tested this with a waveform lighting 3082 Dimmer controlling a LED
    % strip. In this setup channel 1 was the lightstrip. To let that
    % strip flicker at 2 Hz from its lowest to its highest brightness:
    % sinusoid(o,1,255,2) 
    % This will run for 1 minute
    %
    % BK - Sept 2023

    properties         
        % outpuBreakTime and markAfterBreakTime are in units of 10.67 microseconds
        % outputRate is in packets per socond. 0 means as fast as possible (=40 Hz)
        breakTime (1,1) double {mustBeInteger, mustBeInRange(breakTime,9,127)} = 9
        markAfterBreakTime (1,1) double {mustBeInteger, mustBeInRange(markAfterBreakTime,1,127)} =1
        outputRate (1,1) double {mustBeInteger,mustBeInRange(outputRate,1,40)} = 40       
    end

    properties (SetAccess = protected)     
        % Read only properties
        serialNumber (1,1) double
        firmware  (1,1) double                
    end

     properties (SetAccess = protected,Hidden)      
         % Hidden read only properties.
        hSerial   = []     
        userConfig (1,:) double = 255*ones(1,85); % Not sure what this is/does, but my widget had 85 entries of 255 as userConfig. 
        lastDmxOut = datetime("now");
    end

    properties (Constant,Hidden)
        % Constants defining the "labels" in the Enttec API
        REPROGRAMFIRMWARE = 1
        PROGRAMFLASHPAGE  = 2         
        GETWIDGETPARAMETERS = 3        
        SETWIDGETPARAMETERS  = 4
        RECEIVEDDMXPACKET  = 5
        OUTPUTONLYDMX = 6
        RDMPACKET = 7 
        RECEIVEDMXONCHANGE =8
        RECEIVEDDMXCHANGEOFSTATE = 9
        GETWIDGETSERIAL = 10
        SENDRDMDISCOVERY =11            
    end 

    properties (Dependent)
        port
        isConnected
    end

    methods        
        function v = get.isConnected(o)
            % Returns true if a serialport object has been setup for a
            % port.
            v = ~isempty(o.hSerial) && ~isempty(o.hSerial.Port);
        end
        function v = get.port(o)
            % returns the connected port name
            if o.isConnected
                v = o.hSerial.Port;
            else
                v = "NOT CONNECTED";
            end
        end

        % Set functions for the widget parameters; update immediately on
        % the widget.
        function set.breakTime(o,value)
            o.breakTime = value;
            o.setWidgetParameters; % Update
        end
        
        function set.outputRate(o,value)
            o.outputRate= value;
            o.setWidgetParameters; % Update
        end
        function set.markAfterBreakTime(o,value)
            o.markAfterBreakTime = value;
            o.setWidgetParameters; % Update
        end        
        
    end

    methods (Access=public)
        function o = dmxUsbPro(prt)
            % Constructor. Provied the name of the serial COM port
            % (defaults to COM3)
            arguments 
                prt (1,1) string = "COM3"
            end 
            % Try to connect.
            try 
                o.hSerial = serialport(prt,9600);
            catch me
                if strcmpi(me.identifier,'serialport:serialport:ConnectionFailed')
                    fprintf('Could not connect to  %s. Probably you connected to it already? Clear the dmxUsbPro object, or clear all\n',prt)
                else
                    rethrow(me)
                end
            end
            % Make sure the parameters match what is currently set.
            o.setWidgetParameters;
        end
        
        function delete(o)
            close(o)
        end

        function close(o)
            o.hSerial = [] ; % Close the port
        end

        function sinusoid(o,channel,amplitude,frequency,duration)
            %Example function to generate sinusoidal brightness modulation
            % for a single channel in a universe.
            arguments 
                o (1,1) dmxUsbPro
                channel (1,1) {mustBeInteger,mustBeInRange(channel,1,512)}
                amplitude (1,1) {mustBeInRange(amplitude,0,127)}
                frequency (1,1) {mustBeInRange(frequency,0,40)}
                duration (1,1) {mustBeNonnegative} = 60
            end
            tic;
            fprintf('Starting sinusoid loop for %.2f s. Press ctrl-c to terminate.\n',duration)            
            while (toc<60)
                setChannel(o,channel,128+amplitude*sin(2*pi*toc*frequency));
                pause(1/o.outputRate-.005); % Be nice, allow interrupts
            end     
            stopDmxOut(o)
        end
        
        function setChannel(o,channel,value)
            % Convenience to set one or more channels in the universe to a value and
            % the rest to zero.
            arguments
                o (1,1) dmxUsbPro
                channel (1,:) {mustBeInRange(channel,1,512)}
                value (1,1) {mustBeInRange(value,0,255)}
            end
           universe = zeros(1,512);
           universe(channel) =value;
           startDmxOut(o,0,universe);
        end

        function startDmxOut(o,startCode,data)
            % Send a DMX command out into the universe. Keep sending it at
            % the outputRate. 
            % The widget will blink green next to the USB showing the
            % ongoing transmission. To stop it, call stopDmxOut.
            arguments
                o (1,1) dmxUsbPro 
                startCode (1,1)  double {mustBeInteger,mustBeNonnegative}
                data (1,:) double 
             end
            nrDmxChannels = numel(data);
            assert(nrDmxChannels>=24 && nrDmxChannels <=512,"DMX Data must be between 24 and 512 channels");                
            sendPacket(o,o.OUTPUTONLYDMX,[startCode data]);
            o.lastDmxOut = datetime("now");
        end

        function stopDmxOut(o)
            % Any message will do to stop it. Use a simple one.
            % Wait until the last DMX message passed to startDMXOut has been sent out (if needed)
            if second(datetime("now")) -second(o.lastDmxOut) < 1/o.outputRate
                pause(1./o.outputRate);
            end
            getWidgetSerial(o);
        end

        function flush(o)
            % Clear any data on the port
            flush(o.hSerial);
        end

        function [frmware,brkTime,mrkAfterBreakTime,outptRate, userCnfg] = getWidgetParameters(o)
            % Retrieve current parameters on the Widget.
            % Ask for it
            sendPacket(o,o.GETWIDGETPARAMETERS)
            % Retrieve it          
            bytes = getPacket(o,o.GETWIDGETPARAMETERS,5+ numel(o.userConfig));            
            frmware = bytes(1) + bitshift(bytes(2),8);
            brkTime = bytes(3);
            mrkAfterBreakTime = bytes(4);
            outptRate = bytes(5);
            userCnfg  = bytes(6:end);
            if nargout ==0                
                % Update the object
                o.firmware = frmware;
                o.breakTime = brkTime;
                o.markAfterBreakTime = mrkAfterBreakTime;
                o.outputRate = outptRate;
                o.userConfig  = userCnfg;
            end
        end

        function getWidgetSerial(o)
            % Retrieve serial number of the widget. This is supposed to
            % match the number on the box ( but didn't in my case).            
            sendPacket(o,o.GETWIDGETSERIAL);
            bytes = getPacket(o,o.GETWIDGETSERIAL,4);
            thisSerial =0;
            for b=1:numel(bytes)                
                % Little Endian
                thisSerial =thisSerial + bitshift(bytes(b),(b-1)*8);        
            end
            o.serialNumber = thisSerial;            
        end 

    end



    methods (Access=protected)

        function setWidgetParameters(o)
            % Set the new parameters (called by set.xxx())
            sendPacket(o,o.SETWIDGETPARAMETERS)
            % Retrieve the newly set values to make sure it worked ok.
            [~,brkTime,mrkAfterBreakTime,outptRate] = getWidgetParameters(o);
            assert(brkTime==o.breakTime && ...
                    mrkAfterBreakTime==o.markAfterBreakTime && ...
                    outptRate==o.outputRate,"Widget parameters were not set correctly. Please try again.");
        end

        function sendPacket(o,label,dmxData)
            % Send a specific packet to the widget
            switch (label)
                case o.REPROGRAMFIRMWARE
                    fprintf(2,"Reprogram Firmware Request message not implemented yet.\n")
                    return
                case o.PROGRAMFLASHPAGE
                    fprintf(2,"Program Flash Page Request message not implemented yet.\n")                   
                    return
                case o.GETWIDGETPARAMETERS
                     [userLsb,userMsb] = dmxUsbPro.lsbmsb(numel(o.userConfig));
                    pck = dmxUsbPro.packet(label,[userLsb userMsb]);
                case o.SETWIDGETPARAMETERS
                    [userLsb,userMsb] = dmxUsbPro.lsbmsb(numel(o.userConfig));
                    pck =dmxUsbPro.packet(label,[userLsb userMsb o.breakTime o.markAfterBreakTime o.outputRate o.userConfig]);                   
                case o.RECEIVEDDMXPACKET 
                    fprintf(2,"RECEIVEDDMXPACKET message not implemented yet.\n")                   
                    return
                case o.OUTPUTONLYDMX                     
                    pck = dmxUsbPro.packet(label,dmxData);
                case o.RDMPACKET
                    fprintf(2,"RDMPACKET message not implemented yet.\n")                   
                    return
                case o.RECEIVEDMXONCHANGE
                    fprintf(2,"RECEIVEDMXONCHANGE message not implemented yet.\n")                   
                    return
                case o.RECEIVEDDMXCHANGEOFSTATE
                    fprintf(2,"RECEIVEDDMXCHANGEOFSTATE message not implemented yet.\n")                   
                    return
                case o.GETWIDGETSERIAL 
                    pck = dmxUsbPro.packet(label,[]);    
                case o.SENDRDMDISCOVERY
                    fprintf(2,"SENDRDMDISCOVERY Request message not implemented yet.\n")                   
                    return
            end
            flush(o); % Clear out the port
            write(o.hSerial,pck,"uint8");
        end


        function bytes = getPacket(o,label, nrBytesExpected)
            % Retrieve the reply for a specific label from the device.
            arguments 
                o (1,1) dmxUsbPro
                label (1,1) double {mustBeInteger,mustBeNonnegative}
                nrBytesExpected (1,1) double {mustBeInteger,mustBeNonnegative} 
            end            
            nrBytesExpected = nrBytesExpected+5; % Data+ start, stop, msb,lsb, label
            % A little tricky as it depends on no other bytes coming from
            % the widget. The flush(o) before each write should handle that
            % but in a setup where the widget also receives DMX input from
            % elsewhere, this will need some rethinking (a polling loop to
            % detect incoming messages for instance, or better a callback on the 
            % serialport).
            while (o.hSerial.NumBytesAvailable~=nrBytesExpected)
                pause(0.1);
            end
            bytes = read(o.hSerial,o.hSerial.NumBytesAvailable,"uint8");
            nrBytesRead = numel(bytes);
            % Sanity checks
            assert(nrBytesRead==nrBytesExpected,"Message length not correct")
            assert(bytes(2) == label,"Wrong label returned (Expected %d, Received %d)",label,bytes(2));
            dataOffset = 5;
            bytes = bytes(dataOffset:(nrBytesRead-1));
        end
    end

    methods (Static)
        function pck= packet(label,data)
            % Create a data packet to send to the device         
            startCode = 0x7E;
            stopCode = 0xE7;
            nrBytes = numel(data);
            assert(nrBytes<=600,"This data package is too long (%d>600)",nrBytes);                
            [lsb,msb] = dmxUsbPro.lsbmsb(nrBytes);
            pck= uint8([startCode label lsb msb data stopCode]);
        end

        function  [lsb,msb] = lsbmsb(n)
            % Split a number n in a least and most significant byte
            assert(n<intmax('uint16'),"This cannot be represented as a uint16 (%d)",n);
            lsb = bitand(uint16(n),uint16(0xFF));
            msb = bitand(bitshift(uint16(n),-8), uint16(0xFF));
        end
    end
end