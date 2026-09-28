function C_Realistic_Final()
clc; clear; close all;
%% 1. LOAD DATA & SYNC TIMING
aMat = "A_satellite_outputs.mat";
bMat = "B_wind_spread_output.mat";
if ~isfile(aMat) || ~isfile(bMat)
    error("Missing input files. Please ensure Script A and B have been run and saved.");
end
A = load(aMat); B = load(bMat);
S = A.S;
[m, n, ~] = size(S.AFT.RGB);
% Set Simulation Start Time
t0_sim = datetime(2025,7,2,9,4,11);
%% 2. SIMULATION SETTINGS
T_hours     = 4.0;
dt_minutes  = 15;
nSteps      = round(T_hours*60/dt_minutes) + 1;
tVec_h      = (0:nSteps-1)' * (dt_minutes/60);
dt_s        = dt_minutes * 60;
baseRate_mps = 0.008;
windGain_mps = 0.005;
ellipticity  = 2.5;
anisoStrength = 0.85;
dx = 10;
%% 3. INITIALIZE MASKS & GROWTH TRACKER
predMasks = false(m, n, nSteps);
if isempty(S.burnMask) || nnz(S.burnMask) == 0
    error("The burn mask from Script A is empty. Check your dNBR threshold.");
end
predMasks(:,:,1) = logical(S.burnMask);
landMask = ~(S.waterMask);
% Initialize burned area array (m2)
burnedArea_m2 = zeros(nSteps, 1);
pixelArea_m2 = dx * dx;
burnedArea_m2(1) = nnz(predMasks(:,:,1)) * pixelArea_m2;
% Prepare ERA5 timeline alignment
era5_t_hours = hours(datetime(2025,7,2,9,0,0) + hours(0:size(B.uA,3)-1) - t0_sim);
fprintf("Starting Real-Time Wind Integration...\n");
%% 4. SIMULATION LOOP
for k = 2:nSteps
    t_curr = tVec_h(k);
    % Interpolate wind data for current time step
    u_raw = interpTimeStack(B.uA, era5_t_hours, t_curr);
    v_raw = interpTimeStack(B.vA, era5_t_hours, t_curr);
    % Resize wind map to match satellite 10m grid
    u_map = imresize(u_raw, [m, n], 'bilinear');
    v_map = imresize(v_raw, [m, n], 'bilinear');
    % Calculate wind speed and unit vectors
    ws = hypot(u_map, v_map);
    ux = u_map ./ (ws + eps);
    uy = -v_map ./ (ws + eps);
    % Calculate step distance based on local wind speed
    stepDist_m = (baseRate_mps + windGain_mps * ws) * dt_s;
    % Propagate fire front
    prev = predMasks(:,:,k-1);
    next = propagateEfficient(prev, stepDist_m, ux, uy, ellipticity, anisoStrength, dx);
    % Constrain to land (remove water)
    predMasks(:,:,k) = next & landMask;
    % Track growth
    burnedArea_m2(k) = nnz(predMasks(:,:,k)) * pixelArea_m2;
    if mod(k,4)==0
        fprintf('  T+%.1f hours | Mean Wind Speed: %.2f m/s\n', t_curr, mean(ws,'all'));
    end
end
%% 5. DIAGNOSTICS &  OUTPUT
actualPixels = nnz(logical(S.burnMask));
predPixels   = nnz(predMasks(:,:,end));
intersection = predMasks(:,:,end) & logical(S.burnMask);
% Accuracy Metrics
iou = (nnz(intersection) / (actualPixels + predPixels - nnz(intersection))) * 100;
growth_error = ((predPixels - actualPixels) / actualPixels) * 100;
totalGrowth_m2 = burnedArea_m2(end) - burnedArea_m2(1);
% FIXED PRINTING BLOCK
fprintf('\n==========================================\n');
fprintf('       FIRE SPREAD ANALYSIS RESULTS       \n');
fprintf('==========================================\n');
fprintf('Initial Area:    %15.2f m^2\n', burnedArea_m2(1));
fprintf('Final Area:      %15.2f m^2\n', burnedArea_m2(end));
fprintf('------------------------------------------\n');
fprintf('TOTAL GROWTH:    %15.2f m^2\n', totalGrowth_m2);
fprintf('------------------------------------------\n');
fprintf('Final IoU Score: %15.2f %%\n', iou);
fprintf('Area Error:      %15.2f %%\n', growth_error);
fprintf('==========================================\n');
%% 6. VISUALIZATION
figure('Name','Spatial Validation','Position',[100 100 1200 500], 'Color', 'w');
subplot(1,2,1);
imshow(S.AFT.RGB); hold on;
visboundaries(predMasks(:,:,end), 'Color', 'r', 'LineWidth', 2);
title(sprintf('Model Prediction (Red) | IoU: %.1f%%', iou));
subplot(1,2,2);
imshow(S.AFT.RGB); hold on;
visboundaries(logical(S.burnMask), 'Color', 'g', 'LineWidth', 2);
title('Satellite Observation (Green Truth)');
figure('Name','Area Growth Over Time','Position',[200 200 800 400], 'Color', 'w');
plot(tVec_h, burnedArea_m2, '-o', 'Color', [0.85 0.33 0.1], 'LineWidth', 2, 'MarkerSize', 4);
grid on;
xlabel('Simulation Time (Hours)');
ylabel('Burned Area (m^2)');
title('Simulated Fire Growth Rate');
% Save final workspace results
save("C_realistic_results.mat", "predMasks", "iou", "burnedArea_m2", "tVec_h");
fprintf('Results saved to C_realistic_results.mat\n');
end
%% FUNCTIONS
function next = propagateEfficient(prev, dist_m, ux, uy, ellip, aniso, dx)
    [m, n] = size(prev);
    a_px = (dist_m / dx) .* (1 + aniso*(ellip-1));
    b_px = (dist_m / dx);
    base = bwdist(prev) <= mean(b_px, 'all');
    [rr, cc] = ndgrid(1:m, 1:n);
    push_px = max(0, a_px - b_px);
    rr2 = round(rr - uy .* push_px);
    cc2 = round(cc - ux .* push_px);
    valid = (rr2 >= 1 & rr2 <= m & cc2 >= 1 & cc2 <= n);
    adv = false(m, n);
    idx = sub2ind([m, n], rr2(valid), cc2(valid));
    adv(valid) = prev(idx);
    next = base | adv;
end
function val = interpTimeStack(stack, t_vec, t_target)
    idx = find(t_vec <= t_target, 1, 'last');
    if isempty(idx), idx = 1; end
    if idx >= numel(t_vec)
        val = stack(:,:,end);
    else
        f = (t_target - t_vec(idx)) / (t_vec(idx+1) - t_vec(idx));
        val = (1-f)*stack(:,:,idx) + f*stack(:,:,idx+1);
    end
end
