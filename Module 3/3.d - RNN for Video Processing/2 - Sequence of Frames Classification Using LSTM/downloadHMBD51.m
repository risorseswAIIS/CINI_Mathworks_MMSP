downloadFolder = './';

url = "https://serre-lab.clps.brown.edu/wp-content/uploads/2013/10/hmdb51_org.rar";
filename = fullfile(downloadFolder,"hmdb51_org.rar");

dataFolder = fullfile(downloadFolder,"hmdb51_org");

if ~exist(dataFolder,"dir")
    if ~exist(filename,"file")
        fprintf("Downloading HMDB: a large human motion database (2GB)...\n");
        websave(filename,url);
        fprintf("Done!\n");
    end
    fprintf("Please unrar the downloaded file and subfolders in %s\n",dataFolder);
end
   