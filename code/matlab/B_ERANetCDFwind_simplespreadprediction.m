function B_ERANetCDFwind_simplespreadprediction()
clc; clear; close all;
%%USER SETTINGS
aMat   = "A_satellite_outputs.mat";     % Script A output
era5Nc = "C:\Users\yemee\Downloads\project\cdsdata\era5\seferihisar_2025-07-02.nc";
% Start time
t0 = datetime(2025,7,2,9,4,11);
t0.TimeZone = "";
T_hours  = 3;      % horizon 0..3 hours
dt_hours = 1;      % ERA5 often hourly
outMat = "B_wind_spread_output.mat";
%% ------------------------------------------------------------
if ~isfile(aMat),   error("Missing %s. Run Script A first.", aMat); end
if ~isfile(era5Nc), error("Missing ERA5 NetCDF: %s", era5Nc); end
A = load(aMat);
if ~isfield(A,"S"), error("Script A MAT must contain struct S."); end
S = A.S;
if ~isfield(S,"AFT") || ~isfield(S.AFT,"RGB")
    error("Script A must save S.AFT.RGB");
end
[m,n,~] = size(S.AFT.RGB);
AOI = S.AOI;
% Detect variable names
info = ncinfo(era5Nc);
varNames = string({info.Variables.Name});
timeVar = pickFirstOrEmpty(varNames, ["valid_time","time","Time","TIMESTAMP"]);
uVar    = pickFirstOrEmpty(varNames, ["u10","10u","u","U10","u_component_of_wind"]);
vVar    = pickFirstOrEmpty(varNames, ["v10","10v","v","V10","v_component_of_wind"]);
t2mVar  = pickFirstOrEmpty(varNames, ["t2m","2t","T2M","temperature_2m"]);
rVar    = pickFirstOrEmpty(varNames, ["r","RH","relative_humidity","r2m","humidity"]);
latVar  = pickFirstOrEmpty(varNames, ["latitude","lat","Latitude","LAT"]);
lonVar  = pickFirstOrEmpty(varNames, ["longitude","lon","Longitude","LON"]);
fprintf("Detected variables:\n");
fprintf("  timeVar = %s\n", showVar(timeVar));
fprintf("  uVar    = %s\n", showVar(uVar));
fprintf("  vVar    = %s\n", showVar(vVar));
fprintf("  rVar    = %s\n", showVar(rVar));
fprintf("  t2mVar  = %s\n", showVar(t2mVar));
fprintf("  latVar  = %s\n", showVar(latVar));
fprintf("  lonVar  = %s\n\n", showVar(lonVar));
if timeVar == "" || uVar == "" || vVar == ""
    error("ERA5 file must contain time + u + v (or equivalents).");
end
hasT = (t2mVar ~= "");
hasR = (rVar   ~= "");
%% Read coords/time
lat = []; lon = [];
if latVar ~= "" && lonVar ~= ""
    lat = double(ncread(era5Nc, char(latVar)));
    lon = double(ncread(era5Nc, char(lonVar)));
end
tRaw = ncread(era5Nc, char(timeVar));
tDT  = convertCFTimeToDatetime(era5Nc, char(timeVar), tRaw);
tDT.TimeZone = "";
%% Choose times within [t0, t0+T_hours]
t1 = t0 + hours(T_hours);
idxs = find(tDT >= t0 & tDT <= t1);
if isempty(idxs)
    [~,i0] = min(abs(tDT - t0));
    idxs = i0 : min(i0 + round(T_hours/dt_hours), numel(tDT));
end
% [NOTE: the next line is cut off at the right page margin in the report PDF; the rest of the line is not recoverable]
fprintf("Using %d ERA5 steps from %s to %s\n\n", numel(idxs), string(tDT(idxs(1))), string(tDT(idxs(end)
Nt = numel(idxs);
%% Preallocate outputs on AOI grid
uA = zeros(m,n,Nt,'single');
vA = zeros(m,n,Nt,'single');
wsA = zeros(m,n,Nt,'single');
wd_toDeg = zeros(m,n,Nt,'single');
if hasT, t2mA = zeros(m,n,Nt,'single'); else, t2mA = []; end
if hasR, rA   = zeros(m,n,Nt,'single'); else, rA   = []; end
[latGrid, lonGrid] = makeAOIlatlonGrid(AOI, m, n);
%% Read arrays
uAll = ncread(era5Nc, char(uVar));
vAll = ncread(era5Nc, char(vVar));
if hasT, tAll = ncread(era5Nc, char(t2mVar)); end
if hasR, rAll = ncread(era5Nc, char(rVar));   end
for k = 1:Nt
    it = idxs(k);
    U = squeeze(sliceAtTime(uAll, it));
    V = squeeze(sliceAtTime(vAll, it));
    if hasT
        T = squeeze(sliceAtTime(tAll, it));
    else
        T = [];
    end
    if hasR
        RH = squeeze(sliceAtTime(rAll, it));
    else
        RH = [];
    end
    [u2, v2, t2, r2] = alignERA5toAOI(U, V, T, RH, lat, lon, latGrid, lonGrid, m, n);
    uA(:,:,k) = single(u2);
    vA(:,:,k) = single(v2);
    ws = hypot(double(u2), double(v2));
    wsA(:,:,k) = single(ws);
    wd_to = mod(atan2d(double(u2), double(v2)), 360);
    wd_toDeg(:,:,k) = single(wd_to);
    if hasT, t2mA(:,:,k) = single(t2); end
    if hasR, rA(:,:,k)   = single(r2); end
end
%% Compatibility fields for Script C
u  = uA(:,:,1);
v  = vA(:,:,1);
ws = wsA(:,:,1);
wd_toDeg0 = wd_toDeg(:,:,1);
%% Tables (inputs + outputs)
B_table_inputs = table( ...
    string(era5Nc), string(aMat), t0, T_hours, dt_hours, ...
    "VariableNames", ["era5Nc","aMat","t0","T_hours","dt_hours"]);
B_table_outputs = table( ...
    Nt, tDT(idxs(1)), tDT(idxs(end)), ...
    min(wsA,[],"all"), mean(wsA,"all"), max(wsA,[],"all"), ...
    hasT, hasR, ...
    "VariableNames", ["Nt","tStart","tEnd","ws_min","ws_mean","ws_max","hasT","hasR"]);
disp("=== Script B Inputs ===");  disp(B_table_inputs);
disp("=== Script B Outputs ==="); disp(B_table_outputs);
save(outMat, ...
    "t0","T_hours","dt_hours","idxs","tDT", ...
    "uA","vA","wsA","wd_toDeg", ...
    "u","v","ws","wd_toDeg0", ...
    "t2mA","rA","hasT","hasR", ...
    "lat","lon","AOI","m","n", ...
    "B_table_inputs","B_table_outputs");
disp("Saved: " + outMat);
end
%% FUNCTIONS
function s = showVar(v)
if v == "", s="(not found)"; else, s=char(v); end
end
function name = pickFirstOrEmpty(varNames, candidates)
candidates = string(candidates);
name = "";
for k = 1:numel(candidates)
    if any(varNames == candidates(k))
        name = candidates(k);
        return;
    end
end
end
function tDT = convertCFTimeToDatetime(ncFile, timeVarName, tRaw)
units = "";
try, units = string(ncreadatt(ncFile, timeVarName, "units")); catch, end
tRaw = double(tRaw(:));
if strlength(units)==0
    tDT = datetime(1970,1,1,0,0,0) + seconds(tRaw);
    tDT.TimeZone = "";
    return;
end
u = lower(strtrim(units));
parts = split(u, "since");
step = strtrim(parts(1));
originStr = "1970-01-01 00:00:00";
if numel(parts) >= 2, originStr = strtrim(parts(2)); end
origin = parseOriginDatetime(originStr);
switch step
    case {"hours","hour"},   tDT = origin + hours(tRaw);
    case {"minutes","minute"}, tDT = origin + minutes(tRaw);
    case {"seconds","second","sec","secs"}, tDT = origin + seconds(tRaw);
    case {"days","day"},     tDT = origin + days(tRaw);
    otherwise,              tDT = origin + hours(tRaw);
end
tDT.TimeZone = "";
end
function origin = parseOriginDatetime(s)
s = char(strtrim(string(s)));
% [NOTE: the next line is cut off at the right page margin in the report PDF; the rest of the line is not recoverable]
fmts = {'yyyy-MM-dd HH:mm:ss','yyyy-MM-dd''T''HH:mm:ss','yyyy-MM-dd HH:mm','yyyy-MM-dd','yyyy-MM-dd''T''
for i=1:numel(fmts)
    % [NOTE: the next line is cut off at the right page margin in the report PDF; the rest of the line is not recoverable]
    try, origin = datetime(s, "InputFormat", fmts{i}, "TimeZone",""); origin.TimeZone=""; return; catch,
end
origin = datetime(s); origin.TimeZone="";
end
function slice2D = sliceAtTime(A, idxTime)
sz = size(A);
nd = ndims(A);
if nd == 2
    slice2D = A; return;
end
for d = 1:nd
    if idxTime <= sz(d)
        subs = repmat({':'}, 1, nd);
        subs{d} = idxTime;
        try
            tmp = squeeze(A(subs{:}));
            if ismatrix(tmp), slice2D = tmp; return; end
        catch
        end
    end
end
error("Could not slice array at time index %d", idxTime);
end
function [latGrid, lonGrid] = makeAOIlatlonGrid(AOI, m, n)
latVec = linspace(AOI.latMax, AOI.latMin, m);
lonVec = linspace(AOI.lonMin, AOI.lonMax, n);
[lonGrid, latGrid] = meshgrid(lonVec, latVec);
end
function [u2,v2,t2,r2] = alignERA5toAOI(U,V,T,RH, lat, lon, latGrid, lonGrid, m, n)
t2 = []; r2 = [];
if isempty(lat) || isempty(lon) || numel(lat)<2 || numel(lon)<2 || min(size(U))<2
    u2 = repmat(double(U(1)), m, n);
    v2 = repmat(double(V(1)), m, n);
    if ~isempty(T),  t2 = repmat(double(T(1)),  m, n); end
    if ~isempty(RH), r2 = repmat(double(RH(1)), m, n); end
    return;
end
latv = lat(:); lonv = lon(:);
U = double(U); V = double(V);
if latv(1) > latv(end)
    latv = flipud(latv);
    U = flipud(U); V = flipud(V);
    if ~isempty(T),  T  = flipud(double(T));  else, T=[]; end
    if ~isempty(RH), RH = flipud(double(RH)); else, RH=[]; end
else
    if ~isempty(T),  T  = double(T);  end
    if ~isempty(RH), RH = double(RH); end
end
FU = griddedInterpolant({latv, lonv}, U, "linear", "none");
FV = griddedInterpolant({latv, lonv}, V, "linear", "none");
u2 = fillmissing(FU(latGrid, lonGrid), "nearest");
v2 = fillmissing(FV(latGrid, lonGrid), "nearest");
if ~isempty(T)
    FT = griddedInterpolant({latv, lonv}, T, "linear", "none");
    t2 = fillmissing(FT(latGrid, lonGrid), "nearest");
end
if ~isempty(RH)
    FR = griddedInterpolant({latv, lonv}, RH, "linear", "none");
    r2 = fillmissing(FR(latGrid, lonGrid), "nearest");
end
end
