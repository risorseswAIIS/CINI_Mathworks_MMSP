%denoisingImageDatastore_SaltPepper   Denoising image datastore
%
%   A denoisingImageDatastore_saltpepper object encapsulates a datastore which
%   creates batches of noisy image patches and corresponding noise patches
%   to be fed to a denoising deep neural network for training.
%
%   ds = denoisingImageDatastore_SaltPepper(imds) creates a randomly cropped pristine and
%            noisy image patch pair datastore using images from ImageDatastore imds.
%
%   ds = denoisingImageDatastore_SaltPepper(__, Name, Value,__) creates a
%            randomly cropped pristine and noisy patch pair image
%            datastore with additional parameters controlling the data
%            generation process.
%
%   Parameters are:
%
%   PatchesPerImage           : Integer specifying the number of patches 
%                               generated from an image.
%                               Default is 512.
%
%   PatchSize                 : Size of the random crops. It can be an
%                               integer scalar specifying same row and
%                               column sizes or a two element integer
%                               vector specifying different row and column
%                               sizes.
%                               Default: 50.
%
%   DensityNoiseLevel         : Specifies the noise density of "salt and pepper"
%                               noise added to the image. The density specify
%                               how many pixels of the images approximately
%                               will be affected by noise (e.g. D*numel(I)
%                               pixels). It can be a scalar signifying a
%                               single noise level or a vector of two
%                               elements specifying the maximum and minimum
%                               density. When it is a vector, the range of noise 
%                               density is uniformly sampled to identify
%                               a noise density level for a particular patch.
%                               Default: 0.05.
%
%   DispatchInBackground      : Accelerate training patch generation by
%                               asynchronously reading, adding noise, and
%                               queueing them for use in training. Requires
%                               Parallel Computing Toolbox.
%                               Default: false.
%
%   ChannelFormat             : Specifies the data channel format as rgb or
%                               grayscale.
%                               Default: grayscale.
%
%   denoisingImageDatastore_SaltPepper properties:
%       PatchesPerImage         - Number of random patches to be extracted per image
%       PatchSize               - Size of the image patches
%       DensityNoiseLevel       - Salt and pepper noise level
%       ChannelFormat           - Channel format of output noisy patches
%       MiniBatchSize           - Number of patches returned in each read
%       NumObservations         - Total number of patches in an epoch
%       DispatchInBackground    - Whether background dispatch is used
%
%   denoisingImageDatastore_SaltPepper methods:
%       denoisingImageDatastore_SaltPepper - Construct a denoisingImageDatastore_SaltPepper
%       hasdata                 - Returns true if there is more data in the datastore
%       partitionByIndex        - Partitions a denoisingImageDatastore_SaltPepper given indices
%       preview                 - Reads the first image from the datastore
%       read                    - Reads a MiniBatch of data from the datastore
%       readall                 - Reads all observations from the datastore
%       readByIndex             - Random access read from datastore given indices
%       reset                   - Resets datastore to the start of the data
%       shuffle                 - Shuffles the observations in the datastore
%       transform               - Create an altered form of the current datastore by
%                                 specifying a function handle that will execute
%                                 after read on the current datastore.
%       combine                  - Create a new datastore that horizontally
%                                 concatenates the result of read from two or more
%                                 input datastores.
%
%   NOTE: This function requires the Deep Learning Toolbox.
%
%   Class Support
%   -------------
%
%   imds is an ImageDatastore.
%
%   Notes:
%   -----
%
%  1. Training a deep neural network for a range of noise standard
%     deviations is a much more difficult problem compared to a single
%     noise level one. Hence, it is recommended to create more patches
%     compared to a single noise level case and training might take more
%     time.
%
%  2. If channel format is grayscale, all color images would be converted
%     to grayscale and if channel format is rgb, grayscale images would be
%     replicated to simulate an rgb image.
%
%   Example 1 - Train a network using denoisingImageDatastore_SaltPepper
%   -------
%
%   imds = imageDatastore(pathToGrayscaleNaturalImageData);
%
%   ds = denoisingImageDatastore_SaltPepper(imds,...
%       'PatchesPerImage', 512,...
%       'PatchSize', 50,...
%       'DensityNoiseLevel', [0.01 0.1],...
%       'ChannelFormat', 'grayscale');
%
%   layers = dnCNNLayers();
%
%   opts = trainingOptions('sgdm');
%
%   net = trainNetwork(ds,layers,opts);
%
%   Example 2 - Visualize data in denoisingImageDatastore_SaltPepper
%   -------
%
%   imds = imageDatastore(fullfile(matlabroot,'toolbox','images','imdata'));
%   
%   ds = denoisingImageDatastore_SaltPepper(imds,...
%       'PatchesPerImage', 512,...
%       'PatchSize', 50,...
%       'DensityNoiseLevel', [0.01 0.1],...
%       'ChannelFormat', 'grayscale');
%
%   data = read(ds);
%
%   figure
%   montage(data{:,1});
%   title('Noisy input images');
%
%   figure
%   montage(data{:,2})
%   title('Expected noise channel response');
%
%   See also dnCNNLayers, denoiseImage, denoisingNetwork

%   Copyright 2017-2018 The MathWorks, Inc.

classdef denoisingImageDatastore_SaltPepper < ...
        matlab.io.Datastore &...
        matlab.io.datastore.MiniBatchable &...
        matlab.io.datastore.Shuffleable &...
        matlab.io.datastore.BackgroundDispatchable &...
        matlab.io.datastore.PartitionableByIndex &...
        matlab.io.datastore.internal.RandomizedReadable

    properties (SetAccess = private, GetAccess = public)
        
        %PatchesPerImage - Number of random patches per image
        %
        %  Integer specifying the number of random patches generated
        %  from each image in the imageDatastore.
        PatchesPerImage
        
        %PatchSize - Size of the random patches
        %
        %   Size of the random crops created from the images.
        PatchSize
        
        %DensityNoiseLevel - Salt&Pepper noise level
        %
        %   Salt and pepper noise density added to the random image patches. 
        %   It can be a scalar signifying a single
        %   noise level or a vector of two elements specifying the maximum and
        %   minimum noise density.
        DensityNoiseLevel
        
        %ChannelFormat - Format of the noisy image patches
        %
        %   Specifies the format of the output noisy image patches as rgb or grayscale.
        ChannelFormat
    end
    
    properties (Dependent)
        
        %MiniBatchSize - MiniBatch Size
        %
        %   The number of observations returned as rows in the table
        %   returned by the read method.
        MiniBatchSize
    end
    
    properties (SetAccess = 'protected', Dependent)
        
        %NumObservations - Number of observations
        %
        %   The number of observations in the datastore. In the case of
        %   denoisingImageDatastore_SaltPepper, this is the length of the
        %   imageDatastore multiplied by PatchesPerImage. When used for
        %   training, this is the number of patches in one training epoch.
        NumObservations 
    end
    
    properties (Access = private, Hidden, Dependent)
        TotalNumberOfMiniBatches
    end
    
    properties (Access = private)
        imds
    end
   
    properties (Access = private)        
        CurrentMiniBatchIndex
        NumberOfChannels
        MiniBatchSizeInternal
        OrderedIndices
    end
        
    methods
        
        function batchSize = get.MiniBatchSize(self)
            batchSize = self.MiniBatchSizeInternal;
        end
        
        function set.MiniBatchSize(self, batchSize)
            self.MiniBatchSizeInternal = batchSize;
        end
        
        function tnmb = get.TotalNumberOfMiniBatches(self)
            
            tnmb = floor(self.NumObservations/self.MiniBatchSize) + ...
                (mod(self.NumObservations, self.MiniBatchSize) > 0)*1;
            
        end
        
        function numObs = get.NumObservations(self)
            numObs = length(self.OrderedIndices);
        end
             
        function self = denoisingImageDatastore_SaltPepper(imds,varargin)
            %denoisingImageDatastore_SaltPepper   Construct a denoising image datastore
            
            images.internal.requiresNeuralNetworkToolbox(mfilename);
            
            narginchk(1,11);
            
            % Error for gpuArrayInputs
            matlab.images.internal.errorIfgpuArray(imds, varargin{:});
            
            validateImagedatastore(imds);
            options = parseInputs(varargin{:});
            
            self.PatchesPerImage = options.PatchesPerImage;
            self.ChannelFormat = options.ChannelFormat;
            if strcmp(self.ChannelFormat,'rgb')
                self.NumberOfChannels = 3;
            else
                self.NumberOfChannels = 1;
            end
            if numel(options.PatchSize) == 1
                self.PatchSize = [options.PatchSize options.PatchSize self.NumberOfChannels];
            else
                self.PatchSize = [options.PatchSize self.NumberOfChannels];
            end
            self.DensityNoiseLevel = options.DensityNoiseLevel;
            
            self.imds = imds.copy(); % Don't mess with state of imds input.
            self.DispatchInBackground = options.DispatchInBackground;
            self.MiniBatchSize = 128;
            numObservations = self.imds.numpartitions * self.PatchesPerImage;
            self.OrderedIndices = 1:numObservations;
            
            self.reset();
        end
        
    end
    
    methods
        
        function [data,info] = readByIndex(self,indices)
            
            validateIndicesWithinRange(indices,self.NumObservations);
            
            indices = self.OrderedIndices(indices);
            
            imageIndices = ceil(indices/self.PatchesPerImage);
            uniqueImageIndices = unique(imageIndices,'stable');
            
            % Create datastore partition via a copy and index. This is
            % faster than constructing a new datastore with the new
            % files.
            subds = copy(self.imds);
            subds.Files = self.imds.Files(uniqueImageIndices);
            images = subds.readall();
            
            if imageIndices(1) == imageIndices(end)
                [input,response] = self.getNoisyPatches(images, length(indices));
                
            else
                % Count number of patches for each image
                numPatches = zeros(1,length(uniqueImageIndices));
                for i=1:length(uniqueImageIndices)
                    numPatches(i) = sum(imageIndices == uniqueImageIndices(i));
                end
                
                [input,response] = self.getNoisyPatches(images, numPatches);
            end
            data = table(input,response);
            info.CurrentFileIndices = uniqueImageIndices;
        end
        
        function [data,info] = read(self)
            
            if ~self.hasdata()
               error(message('images:denoisingImageDatastore_SaltPepper:outOfData')); 
            end
            
            batchNumber = self.CurrentMiniBatchIndex;
            startObsIndex = (batchNumber - 1) * self.MiniBatchSize + 1;
            if batchNumber == self.TotalNumberOfMiniBatches
                endObsIndex = self.NumObservations;
            else
                endObsIndex = startObsIndex + self.MiniBatchSize - 1;
            end
            
            self.CurrentMiniBatchIndex = self.CurrentMiniBatchIndex + 1;
            [data,info] = self.readByIndex(startObsIndex:endObsIndex);
        end
        
        function reset(self)
            self.imds.reset();
            self.CurrentMiniBatchIndex = 1;
        end
        
        function newds = shuffle(self)
            newds = copy(self);
            imdsIndexList = randperm(self.imds.numpartitions);
            reorderIndexList(newds,imdsIndexList);
        end
        
        function TF = hasdata(self)
           TF = self.CurrentMiniBatchIndex <= self.TotalNumberOfMiniBatches;
        end
        
        function newds = partitionByIndex(self,indices)
            validateIndicesWithinRange(indices,self.NumObservations);
            newds = copy(self);
            newds.imds = copy(self.imds);
            newds.OrderedIndices = indices;
        end
               
    end
    
    methods (Hidden)
        function frac = progress(self)
            frac = self.CurrentMiniBatchIndex / self.TotalNumberOfMiniBatches;
        end
    end
   
    methods (Access = private)
        
        function reorderIndexList(self,imdsIndexList)
           % Reorder OrderedIndices to be consistent with a new ordering of
           % the underlying imds. That is, when shuffle is called, we only
           % want to reorder imds, we don't want to end up with a truly
           % random shuffling of all of the observations because that will
           % drastically degrade performance by creating a situation where
           % each image patch is from a different source image.
            
           observationToImdsIndex = floor(( self.OrderedIndices -1) / self.PatchesPerImage) + 1;
           newObservationMapping = zeros(size(observationToImdsIndex),'like',observationToImdsIndex);
           currentIdxPos = 1;
           for i = 1:length(imdsIndexList)
              idx = imdsIndexList(i);
              sortedIdx = find(observationToImdsIndex == idx);
              newObservationMapping(currentIdxPos:(currentIdxPos+length(sortedIdx)-1)) = sortedIdx;
              currentIdxPos = currentIdxPos+length(sortedIdx);
           end
           self.OrderedIndices = newObservationMapping;
        end
        
        function [X,Y] = getNoisyPatches(self, images, numPatches)
            totalPatches = sum(numPatches);
            
            actualPatchSize = [self.PatchSize totalPatches];
            
            X = cell(totalPatches,1);
            Y = cell(totalPatches,1);
            
            isNoiseRange = (numel(self.DensityNoiseLevel) == 2);
            
            count = 1;
            for imIndex = 1:length(numPatches)
                
                im = images{imIndex};
                
                patchSizeCheck = size(im,1) >= actualPatchSize(1) && ...
                    size(im,2) >= actualPatchSize(2);
                
                if ~patchSizeCheck
                    [~,fn,fe] = fileparts(self.imds.Files{imIndex}); 
                    error(message('images:denoisingImageDatastore_SaltPepper:expectPatchSmallerThanImage', [fn fe]));
                end
                                
                if strcmp(self.ChannelFormat,'rgb')
                    im = convertGrayscaleToRGB(im);
                else
                    im = convertRGBToGrayscale(im);
                end
                
                im = im2single(im);
                imNumPatches = numPatches(imIndex);
                
                rowLocations = randi(max(size(im,1)-actualPatchSize(1),1), imNumPatches, 1);
                colLocations = randi(max(size(im,2)-actualPatchSize(2),1), imNumPatches, 1);
                
                for index = 1:imNumPatches
                    patch = im(rowLocations(index):rowLocations(index)+actualPatchSize(1)-1,...
                        colLocations(index):colLocations(index)+actualPatchSize(2)-1, :);
                    
                    if isNoiseRange
                        noiseDensity = min(self.DensityNoiseLevel) + ...
                            abs(self.DensityNoiseLevel(2)-self.DensityNoiseLevel(1))*rand;
                    else
                        noiseDensity = self.DensityNoiseLevel;
                    end
                    
                    X{count} = patch;
                    
                    x = rand(self.PatchSize,'single');
                    X{count}(x < noiseDensity/2) = 0; % Minimum value
                    X{count}(x >= noiseDensity/2 & x < noiseDensity) = 1; % Maximum (saturated) value
                    
                    Y{count} = X{count} - patch;
                    %X{count} = patch + residualNoise;
                    count = count + 1;
                end
            end
        end
        
    end
    
    methods(Static, Hidden = true)
        function self = loadobj(S)
            self = denoisingImageDatastore_SaltPepper(S.imds, ...
                'ChannelFormat', S.ChannelFormat, ...
                'DensityNoiseLevel', S.DensityNoiseLevel,...
                'PatchesPerImage', S.PatchesPerImage,...
                'PatchSize', [S.PatchSize(1) S.PatchSize(2)], ...
                'BackgroundExecution', S.BackgroundExecution);
        end
    end
    
    methods (Hidden)
        function S = saveobj(self)
            
            % Serialize denoisingImageDatastore_SaltPepper object
            % Note we that serialize DispatchInBackground under the name
            % BackgroundExecution to make V1 and V2 loadobj work.
            S = struct('imds',self.imds,...
                'ChannelFormat',self.ChannelFormat,...
                'DensityNoiseLevel',self.DensityNoiseLevel,...
                'PatchesPerImage',self.PatchesPerImage,...
                'PatchSize',self.PatchSize,...
                'BackgroundExecution',self.DispatchInBackground);            
        end
        
    end
end


function B = validateImagedatastore(ds)

validateattributes(ds, {'matlab.io.datastore.ImageDatastore'}, ...
    {'nonempty','vector'}, mfilename, 'IMDS');
validateattributes(ds.Files, {'cell'}, {'nonempty'}, mfilename, 'IMDS');

B = true;

end

function options = parseInputs(varargin)

parser = inputParser();
parser.addParameter('PatchesPerImage',512,@validatePatchesPerImage);
parser.addParameter('PatchSize',50,@validatePatchSize);
parser.addParameter('DensityNoiseLevel',0.05,@validateDensityNoiseLevel);
parser.addParameter('BackgroundExecution',false,@validateBackgroundExecution);
parser.addParameter('DispatchInBackground',false,@validateDispatchInBackground);
parser.addParameter('ChannelFormat','grayscale',@validateChannelFormat);

parser.parse(varargin{:});
options = manageDispatchInBackgroundNameValue(parser);

validOptions = {'rgb','grayscale'};
options.ChannelFormat = validatestring(options.ChannelFormat,validOptions, ...
    mfilename,'ChannelFormat');

end

function B = validatePatchesPerImage(PatchesPerImage)

attributes = {'nonempty','real','scalar', ...
    'positive','integer','finite','nonsparse','nonnan','nonzero'};

validateattributes(PatchesPerImage,images.internal.iptnumerictypes, attributes,...
    mfilename,'PatchesPerImage');

B = true;

end


function B = validatePatchSize(PatchSize)

attributes = {'nonempty','real','vector', ...
    'positive','integer','finite','nonsparse','nonnan','nonzero'};

validateattributes(PatchSize,images.internal.iptnumerictypes, attributes,...
    mfilename,'PatchSize');

if numel(PatchSize) > 2
    error(message('images:denoisingImageDatastore_SaltPepper:invalidPatchSize'));
end

B = true;

end

function B = validateBackgroundExecution(BackgroundExecution)

attributes = {'nonempty','scalar', ...
    'finite','nonsparse','nonnan'};
validateattributes(BackgroundExecution,{'logical'}, attributes,...
    mfilename,'BackgroundExecution');

B = true;

end

function B = validateDispatchInBackground(BackgroundExecution)

attributes = {'nonempty','scalar', ...
    'finite','nonsparse','nonnan'};
validateattributes(BackgroundExecution,{'logical'}, attributes,...
    mfilename,'DispatchInBackground');

B = true;

end

function B = validateDensityNoiseLevel(DensityNoiseLevel)

supportedClasses = {'single','double'};
attributes = {'nonempty','real','vector', ...
    'nonnegative','finite','nonsparse','nonnan','nonzero','>=',0,'<=',1};

validateattributes(DensityNoiseLevel, supportedClasses, attributes,...
    mfilename,'DensityNoiseLevel');

if numel(DensityNoiseLevel) > 2
    error(message('images:denoisingImageDatastore_SaltPepper:invalidNoiseDensity'));
end

B = true;

end

function B = validateChannelFormat(ChannelFormat)

supportedClasses = {'char','string'};
attributes = {'nonempty'};
validateattributes(ChannelFormat,supportedClasses,attributes,mfilename, ...
    'ChannelFormat');

B = true;
end

function im = convertRGBToGrayscale(im)
if ndims(im) == 3
    im = rgb2gray(im);
end
end

function im = convertGrayscaleToRGB(im)
if size(im,3) == 1
    im = repmat(im,[1 1 3]);
end
end

function resultsStruct = manageDispatchInBackgroundNameValue(p)

resultsStruct = p.Results;

DispatchInBackgroundSpecified = ~any(strncmp('DispatchInBackground',p.UsingDefaults,length('DispatchInBackground')));
BackgroundExecutionSpecified = ~any(strncmp('BackgroundExecution',p.UsingDefaults,length('BackgroundExecution')));

% In R2017b, BackgroundExecution was name used to control
% DispatchInBackground. Allow either to be specified.
if BackgroundExecutionSpecified && ~DispatchInBackgroundSpecified
    resultsStruct.DispatchInBackground = resultsStruct.BackgroundExecution;
end

end

function validateIndicesWithinRange(idx,numObservations)
if any((idx < 1) | (idx > numObservations))
   error(message('images:denoisingImageDatastore_SaltPepper:invalidIndex')); 
end
end

