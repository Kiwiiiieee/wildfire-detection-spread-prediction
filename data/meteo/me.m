gribFileName = 'C:\Users\akaou\OneDrive\Desktop\AE-404\Term Project\meteo\data.grib'; 
data = readgeoraster(gribFileName); 
csvFileName = 'C:\Users\akaou\OneDrive\Desktop\AE-404\Term Project\meteo\data.csv'; 
writematrix(data, csvFileName);