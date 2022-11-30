%This script will download the  Drum Sound Effects dataset in the current
%directory

url = 'http://deepyeti.ucsd.edu/cdonahue/wavegan/data/drums.tar.gz';
downloadFolder = './';
filename = fullfile(downloadFolder,'drums_dataset.tgz');

drumsFolder = fullfile(downloadFolder,'drums');
if ~exist(drumsFolder,'dir') 
    disp('Downloading Drum Sound Effects Dataset (218 MB)...')
    websave(filename,url);
    untar(filename,downloadFolder)
end