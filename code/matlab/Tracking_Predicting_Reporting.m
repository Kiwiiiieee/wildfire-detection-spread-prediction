%% =========================================================
%% LOAD ERA5 WEATHER DATA FROM NETCDF (.nc)
%% =========================================================

ncfile = 'data_stream-oper_stepType-instant.nc';

% Read coordinates
lat_era = ncread(ncfile,'latitude');
lon_era = ncread(ncfile,'longitude');
time_era = ncread(ncfile,'time');   % hours since reference

% Read variables
u10 = ncread(ncfile,'u10');   % zonal wind (m/s)
v10 = ncread(ncfile,'v10');   % meridional wind (m/s)
T2 = ncread(ncfile,'t2m');    % temperature (K)
Td2 = ncread(ncfile,'d2m');   % dew point (K)

%% TIME-DEPENDENT FIRE SPREAD (0–3 HOURS)
t0 = 12;        % starting hour index (adjust if needed)
Tmax = 3;       % prediction horizon (hours)
Nt = Tmax + 1;  % 0,1,2,3

%% CONVERT ERA5 VARIABLES

% Slice time window
u10 = u10(:,:,t0:t0+Tmax);
v10 = v10(:,:,t0:t0+Tmax);
T2  = T2(:,:,t0:t0+Tmax);
Td2 = Td2(:,:,t0:t0+Tmax);

% Wind speed and direction
wind_speed = sqrt(u10.^2 + v10.^2);
wind_dir = atan2(v10, u10);   % radians (TO direction)

% Temperature (K → °C)
temperature = T2 - 273.15;

% Relative humidity from dew point
RH = 100 .* exp((17.625 .* (Td2-273.15)) ./ (243.04 + (Td2-273.15))) ./ exp((17.625 .* (T2-273.15)) ./ (243.04 + (T2-273.15)));


%% INTERPOLATE WEATHER TO FIRE GRID

[lonERA, latERA] = meshgrid(lon_era, lat_era);

wind_speed_i = zeros([size(fireHeatmap), Nt]);
wind_dir_i   = zeros([size(fireHeatmap), Nt]);
temp_i       = zeros([size(fireHeatmap), Nt]);
RH_i         = zeros([size(fireHeatmap), Nt]);

for t = 1:Nt
    wind_speed_i(:,:,t) = interp2(lonERA, latERA, wind_speed(:,:,t)', lonGrid, latGrid);
    wind_dir_i(:,:,t)   = interp2(lonERA, latERA, wind_dir(:,:,t)',   lonGrid, latGrid);
    temp_i(:,:,t)       = interp2(lonERA, latERA, temperature(:,:,t)', lonGrid, latGrid);
    RH_i(:,:,t)         = interp2(lonERA, latERA, RH(:,:,t)',          lonGrid, latGrid);
end


%% TIME-DEPENDENT FIRE SPREAD USING ERA5

fireSpread = zeros([size(fireHeatmap), Nt]);
fireSpread(:,:,1) = fireHeatmap;

kernel_size = 21;
[xk, yk] = meshgrid(linspace(-1,1,kernel_size));

for t = 2:Nt

    ws = wind_speed_i(:,:,t);
    theta = wind_dir_i(:,:,t);

    temp_factor = rescale(temp_i(:,:,t), 10, 40);
    humidity_factor = 1 - RH_i(:,:,t)/100;
    env_factor = temp_factor .* humidity_factor;

    kernel = exp((xk.*cos(mean(theta(:))) + yk.*sin(mean(theta(:)))) .* mean(ws(:))).* exp(-(xk.^2 + yk.^2)*4);

    kernel = kernel / sum(kernel(:));

    fireSpread(:,:,t) = conv2(fireSpread(:,:,t-1), kernel, 'same');
    fireSpread(:,:,t) = fireSpread(:,:,t) .* env_factor;
    fireSpread(:,:,t) = fireSpread(:,:,t) / max(fireSpread(:,:,t),[],'all');
end


%% INTERACTIVE FIRE TRACKING DASHBOARD

fig = figure('Name','Fire Spread Tracking','Position',[300 100 900 700]);

ax = axes(fig);
hImg = imagesc(fireSpread(:,:,1),'Parent',ax);
axis image;
colormap hot;
colorbar;
title(ax,'Fire Spread Prediction (t = 0 h)');

% Slider
sld = uicontrol('Style','slider','Min',1,'Max',Nt,'Value',1,'SliderStep',[1/(Nt-1) 1/(Nt-1)],'Position',[150 20 600 20]);
lbl = uicontrol('Style','text','Position',[400 50 200 20],'String','t = 0 hours');

% Slider callback
sld.Callback = @(src,~) updateFire(src, hImg, lbl, fireSpread);

function updateFire(src, hImg, lbl, fireSpread)
    t = round(src.Value);
    hImg.CData = fireSpread(:,:,t);
    lbl.String = sprintf('t = %d hour(s)', t-1);
end