clc, clear, close all
%% COST-231 path loss & received power

f = 800e6;         % Frequency (Hz)
d = linspace(1e3, 30e3, 100); % 1–30 km
Pt = 30;           % Tx Power (dBm)
Gt = 5;            % Tx Gain (dBi)
Gr = 15;           % Rx Gain (dBi)

ht = 30;   % Tx height (m)
hr = 10;   % Rx height (m)

a_hr = (1.1*log10(f/1e6) - 0.7)*hr - (1.56*log10(f/1e6) - 0.8);

PL = 46.3 + 33.9*log10(f/1e6) - 13.82*log10(ht) - a_hr + (44.9 - 6.55*log10(ht))*log10(d/1e3);
Pr = Pt + Gt + Gr - PL;

% LTE sensitivity and margin
Psens = -100;        % dBm
margin = 10;         % dB
Psafe = Psens + margin;

% Find distances
d0 = interp1(Pr, d, Psens);    % 0 dB margin distance
d10 = interp1(Pr, d, Psafe);   % +10 dB margin distance

figure
plot(d/1e3, Pr,'LineWidth',2)
hold on
yline(Psens,'r--','LTE Sensitivity (-100 dBm)','LineWidth',1.5)
yline(Psafe,'g--','+10 dB Margin (-90 dBm)','LineWidth',1.5)

plot(d0/1e3, Psens,'ro','MarkerSize',8,'MarkerFaceColor','r')
plot(d10/1e3, Psafe,'go','MarkerSize',8,'MarkerFaceColor','g')

text(d0/1e3, Psens+2, sprintf('%.1f km (0 dB)', d0/1e3))
text(d10/1e3, Psafe+2, sprintf('%.1f km (+10 dB)', d10/1e3))

xlabel("Distance (km)")
ylabel("Received Power (dBm)")
title("LTE NLOS Link Budget with Link Margin")
grid on

disp(['Received Power = ', num2str(Pr), ' dBm'])

% BER vs SNR (QPSK)
snr = 0:1:20;
ber = berawgn(snr,'psk',4,'nondiff');
figure
semilogy(snr,ber,'LineWidth',2)
grid on
xlabel('SNR (dB)')
ylabel('BER')
title('QPSK Performance for Fire Alert Link')

% Antenna Radiation Pattern (Tx & Rx)
theta = linspace(0,2*pi,1000);

TxPattern = Gt * abs(cos(theta));
RxPattern = Gr * abs(cos(theta).^4);

figure
polarplot(theta, TxPattern, 'LineWidth',2)
hold on
polarplot(theta, RxPattern, 'LineWidth',2)
title('Antenna Radiation Patterns at 800 MHz')
legend('Tx Omnidirectional','Rx Directional')

% Constellation Diagram 
data = randi([0 3],1000,1);
modSig = pskmod(data,4,pi/4);

figure
scatterplot(modSig)
title('QPSK Constellation Diagram for Alert Transmission')

%% Alert triggering based on confidence and burned area
C_min = 0.75;        % minimum detection confidence
A_min = 1e4;         % minimum burned area (m^2)

C = 0.82;            % example detection confidence
A = 2.3e4;           % example burned area

alertFlag = (C >= C_min) && (A >= A_min);

fprintf("Alert Triggered: %d\n", alertFlag);

%% ==============================
% 3D Antenna Radiation Patterns
% ==============================

% Angular grids
theta = linspace(0, pi, 180);        % elevation
phi   = linspace(0, 2*pi, 360);      % azimuth
[TH, PH] = meshgrid(theta, phi);

% Antenna gains (linear scale)
Gtlin = 10^(5/10);     % Tx gain ~ 5 dBi
Grlin = 10^(15/10);    % Rx gain ~ 15 dBi

% Radiation patterns
TxPattern = Gtlin * abs(sin(TH));           % quasi-omnidirectional
TH_tilt = TH - deg2rad(5);
RxPattern = Grlin * abs(cos(TH_tilt)).^4;      % narrow beam directional

% Convert to Cartesian coordinates
[Xt,Yt,Zt] = sph2cart(PH, pi/2 - TH, TxPattern);
[Xr,Yr,Zr] = sph2cart(PH, pi/2 - TH, RxPattern);

%% ==============================
% Plot Transmit Antenna Pattern
% ==============================
figure
surf(Xt, Yt, Zt, TxPattern, 'EdgeColor','none')
axis equal
title('3D Transmit Antenna Radiation Pattern (Alert Node)')
xlabel('X'); ylabel('Y'); zlabel('Z')
colorbar
view(45,30)
lighting gouraud
camlight headlight

%% ==============================
% Plot Receive Antenna Pattern
% ==============================
figure
surf(Xr, Yr, Zr, RxPattern, 'EdgeColor','none')
axis equal
title('3D Receive Antenna Radiation Pattern (AFAD Base Station)')
xlabel('X'); ylabel('Y'); zlabel('Z')
colorbar
view(45,30)
lighting gouraud
camlight headlight
