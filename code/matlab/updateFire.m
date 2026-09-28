function updateFire(src, hImg, lbl, fireSpread)
    t = round(src.Value);
    hImg.CData = fireSpread(:,:,t);
    lbl.String = sprintf('t = %d hour(s)', t-1);
end