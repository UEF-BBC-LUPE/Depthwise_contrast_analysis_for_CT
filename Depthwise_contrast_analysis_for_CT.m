function [PROFILES_NORMALIZED, PROFILES_ORIGINAL, info, SUBIM] = Depthwise_contrast_analysis_for_CT
%% m-file for analysing uCT-figures depth-depentently
%% Intended for 7 mm osteochondral plugs. Change used diameter in create_SUBIM() function 
%% Gives the same pixel values as Analyze, so you can use the Google Drive instructions to convert to HU
%% If you want linear attenuation, uncomment line 100
%% (c) Janne Mäkelä 06/2017
%% Made in a hurry. Could be 10^12 times more effective, but seems to be doing the job
%% Especially orientation-function is really inefficient 

clear all, close all, clc;

lowerlimit = -10000; %Excludes all the pixels below this. Background needs to be excluded in order to calculate averages correctly without the background
% For CA4+ -100 is a good treshold
% Between -100 and -10000 no difference in TaO2 Nanoparticle measurements

% upperlimit = 3000; %Upper limit can be added

% LOAD IMAGES %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%[Dicoms, info] = load_dicoms;   %Load DCM
[Dicoms, info] = load_tifs;    %Load tif (load_dicoms fucntion copied and modified for tifs. Use native pixel values = comment line 24)

%Function for an average image from slides for picking plugs
createdicommasks(Dicoms);

%HU conversion for Dicoms
%Dicoms = Dicoms.*info.RescaleSlope+info.RescaleIntercept; %Uses the same pixel values as Analyze (The script is optimized for this scale)
% Otherwise handles data using native pixel values (original, short integer value)

%HU conversion for tifs
%rescale_coff = calibrate_scale(Dicoms);
%Dicoms = Dicoms.*rescale_coff(1)+rescale_coff(2); %Converting to HU
% Otherwise handles data using native pixel values (original, short integer value)

% % % % % % % % % % % % % % % % % % % % % % % % % % % 

%Preallocating variables to save the measured locations
xcoord_o = [];
ycoord_o = [];

% % Thegreatdecider decides whether execution is continued
Thegreatdecider = 1;

N = 0; %Index of cycles
while Thegreatdecider == 1
N = N+1;
    
%Pick and create subimage
[SUBIM, xcoord_o, ycoord_o] = create_SUBIM(Dicoms, N, xcoord_o, ycoord_o);
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % 

% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % 
% Substituting background with zeros
SUBIM(SUBIM<=lowerlimit) = 0;
% SUBIM(SUBIM>=upperlimit) = 0; %Not used

% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % 

dicom_slider(SUBIM,100) %Using dicom_slider.m function for viewing

% % % % % % % % % % % % % % % % % % % % % % % % % % % 

% Creates point-of-views from both directions
[dicom_swmask, dicom_swmask_y] = maskcreator(SUBIM);

% % % % % % % % % % % % % % % % % % % % % % % % % % % 

slider_question = menu('Does the figure need to be aligned:','1) Yes','2) No');

while slider_question < 3
% % % % % % % % % % % % % % % % % % % % % % % % % % % 

%Creates a image stack from x-angle (ROT_SUBIM) and if needed, orientates the image
ROT_SUBIM = orientation(SUBIM, dicom_swmask, dicom_swmask_y,slider_question);

if slider_question == 1 %Make a new SUBIM and ask for a new run
    
    %For re-orienting, create new original image stack SUBIM
    clear SUBIM
    h = waitbar(0,'Creating a new image stack, please wait...'); %Display waitbar
    for i = 1:size(ROT_SUBIM,3)
        for j = 1:size(ROT_SUBIM,1)
            SUBIM(:,i,j) = ROT_SUBIM(j,:,i);
        end
        waitbar(i/size(ROT_SUBIM,3));
    end
    close(h)
    close figure 100;
    dicom_slider(SUBIM,100) %Using dicom_slider.m function for viewing
    
    %Make new masks
    [dicom_swmask, dicom_swmask_y] = maskcreator(SUBIM);
    
    new_question = menu('Does the figure still need to be aligned:','1) Yes','2) No');
else
    slider_question = 3;
    new_question = 2;
end

if new_question == 2
    slider_question = 3; %moving on from while
end

end

% % % % % % Calculate averages from slices %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
result = calculate_pixelvalues(ROT_SUBIM);

% Uncomment if you want results in linear attenuation coefficient (mu [1/cm])
% result = ((result - info.RescaleIntercept ) / info.RescaleSlope) ./ info.Private_0029_1000; %Divided by 4096 -> linear attenuation coefficient mu
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % 
% uncomment the following if you want mu to mg HA/ccm
% result = result.*info.RescaleSlope+info.RescaleIntercept; 


%Add into overall results:
PROFILES_ORIGINAL{N} = result;
%And the same normalized to 100 points
PROFILES_NORMALIZED(:,N) = interp1(linspace(1,100,numel(result)), result, [1:100]);

% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % 

Thegreatdecider = Ultimatequestion(); % Asks if you want to continue

end %while Thegreatdecider

% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % 
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % 
% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % 
% Subfunctions below

%%
    function [Dicoms, info] = load_dicoms()
        
path = uigetdir; %Choose the folder where the DICOMS are

f = filesep; %Checks what's the file separator for current operating system (windows,unix,linux)

dicomnames = dir([num2str(path) f '*.DCM*']); %Read dicoms. 
disp(['Folder: ', dicomnames(1).folder]); %display folder
%Dicom info
info = dicominfo([num2str(path) f dicomnames(1).name]);

h = waitbar(0,'Loading dicoms, please wait...'); %Display waitbar

%Import dicoms
% % % % % % % % % % % % % % %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%Preallocating to save speed (With 2.08s, without, 2.56s on i5-6267U processor)
temp = dicomread([num2str(path) f dicomnames(1).name]);
Dicoms= int16(zeros(size(temp,1),size(temp,2), length(dicomnames)));

for i = 1:length(dicomnames)
    Dicoms(:,:,i)= dicomread([num2str(path) f dicomnames(i).name]);
    waitbar(i/length(dicomnames));
end
close(h);

    end
%%
    function [Dicoms, info] = load_tifs()
        
path = uigetdir; %Choose the folder where the DICOMS are

f = filesep; %Checks what's the file separator for current operating system (windows,unix,linux)

dicomnames = dir([num2str(path) f '*.tif*']); %Read dicoms. 
disp(['Folder: ', dicomnames(1).folder]); %display folder
%Dicom info
info = imfinfo([num2str(path) f dicomnames(1).name]);

h = waitbar(0,'Loading dicoms, please wait...'); %Display waitbar

%Import dicoms
% % % % % % % % % % % % % % %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%imread overflows values over 32767. Use TIFF class instead.   

%Preallocating to save speed (With 2.08s, without, 2.56s on i5-6267U processor)
%temp = imread([num2str(path) f dicomnames(1).name]);
%Dicoms= int16(zeros(size(temp,1),size(temp,2), length(dicomnames)));

%Preallocation
temp = Tiff([num2str(path) f dicomnames(1).name],'r');
temp = read(temp);
Dicoms= uint16(zeros(size(temp,1),size(temp,2), length(dicomnames)));

for i = 1:length(dicomnames)
    Dicoms(:,:,i)= read(Tiff([num2str(path) f dicomnames(i).name]));
    waitbar(i/length(dicomnames));
end
close(h);

    end

%%
    function createdicommasks(Dicoms)
        
        %Finding where there is cartilage in the image
%Basically a Mask so that it is easy to pick the plugs
%Commented can be used to create black and white figures
% % % h = waitbar(0,'Creating Masks, please wait...'); %Display waitbar
% % % for i = 1:size(Dicoms,1) %y-direction
% % %     for j = 1:size(Dicoms,2) %x-direction
% % %         if find(Dicoms(i,j,:) > 0) %Look for anything
% % %             dicom_mask(i,j,:) = 1;
% % %         else
% % %             dicom_mask(i,j,:) = 0;
% % %         end
% % %     end
% % %     waitbar(i/(size(Dicoms,1)));
% % % end
% % % close(h);

%Or just take an average. Faster and creates a better image
dicom_mask = mean(Dicoms,3);

figure(1); %Mask image
%imshow(dicom_mask)
imagesc(dicom_mask)
axis equal;
hold on;

    end
%%
    function [coefficients] = calibrate_scale(Dicoms)
% To convert images to HU %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Gives out the fit coefficients

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Square size
    % Edit how you like. 
    square_radius1 = 30; %110; %Square size
    square_radius2 = 50; %using 100 does fit, but just barely
    buffer = 5; %How much of the figure is cropped from corners
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% Or pick manually %%
question = 2;
while question == 2

pause(0.5); %Gets rid off random freezing in linux
figure(1);

title(['Please first pick air and then water']);

[xcoord, ycoord] = ginput(2); 
xcoord = floor(xcoord);
ycoord = floor(ycoord);

% Drawing the latest rectangle where the subimages are taken
%{
for i = 1:2
    text(xcoord(i),ycoord(i),num2str(i),'HorizontalAlignment','center');
    window(:,:,i) = [xcoord(i)-square_radius xcoord(i)+square_radius; ycoord(i)-square_radius ycoord(i)+square_radius]; %EDIT THIS IF YOU NEED TO GO THROUGH MORE
    line([window(1,1,i) window(1,2,i)], [window(2,1,i) window(2,1,i)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,2,i) window(1,2,i)], [window(2,1,i) window(2,2,i)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1,i) window(1,2,i)], [window(2,2,i) window(2,2,i)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1,i) window(1,1,i)], [window(2,1,i) window(2,2,i)],'Color','red','LineStyle','-','Linewidth', 2);
end
%}
    %SQUARE RADIUS 1 FOR AIR
    text(xcoord(1),ycoord(1),num2str(1),'HorizontalAlignment','center');

    window(:,:,1) = [xcoord(1)-square_radius1 xcoord(1)+square_radius1; ycoord(1)-square_radius1 ycoord(1)+square_radius1]; %EDIT THIS IF YOU NEED TO GO THROUGH MORE
    line([window(1,1,1) window(1,2,1)], [window(2,1,1) window(2,1,1)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,2,1) window(1,2,1)], [window(2,1,1) window(2,2,1)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1,1) window(1,2,1)], [window(2,2,1) window(2,2,1)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1,1) window(1,1,1)], [window(2,1,1) window(2,2,1)],'Color','red','LineStyle','-','Linewidth', 2);

    %SQUARE RADIUS 2 FOR WATER
    text(xcoord(2),ycoord(2),num2str(2),'HorizontalAlignment','center');

    window(:,:,2) = [xcoord(2)-square_radius2 xcoord(2)+square_radius2; ycoord(2)-square_radius2 ycoord(2)+square_radius2]; %EDIT THIS IF YOU NEED TO GO THROUGH MORE
    line([window(1,1,2) window(1,2,2)], [window(2,1,2) window(2,1,2)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,2,2) window(1,2,2)], [window(2,1,2) window(2,2,2)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1,2) window(1,2,2)], [window(2,2,2) window(2,2,2)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1,2) window(1,1,2)], [window(2,1,2) window(2,2,2)],'Color','red','LineStyle','-','Linewidth', 2);
    
    
%end

question = menu('Satisfied?','1) Yes','2) No');

if question == 2
createdicommasks(Dicoms) %Just plotting the figure again
%plots older rectangles again
%{
for i = 1:2 %NOT TESTED
    text(xcoord(i),ycoord(i),num2str(i),'HorizontalAlignment','center');
    window(:,:,i)= [xcoord(i)-square_radius xcoord(i)+square_radius; ycoord(i)-square_radius ycoord(i)+square_radius]; %EDIT THIS IF YOU NEED TO GO THROUGH MORE
    line([window(1,1,i) window(1,2,i)], [window(2,1,i) window(2,1,i)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,2,i) window(1,2,i)], [window(2,1,i) window(2,2,i)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1,i) window(1,2,i)], [window(2,2,i) window(2,2,i)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1,i) window(1,1,i)], [window(2,1,i) window(2,2,i)],'Color','red','LineStyle','-','Linewidth', 2);
end
%}
%NOT TESTED
    text(xcoord(1),ycoord(1),num2str(1),'HorizontalAlignment','center');

    window(:,:,1) = [xcoord(1)-square_radius1 xcoord(1)+square_radius1; ycoord(1)-square_radius1 ycoord(1)+square_radius1]; %EDIT THIS IF YOU NEED TO GO THROUGH MORE
    line([window(1,1,1) window(1,2,1)], [window(2,1,1) window(2,1,1)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,2,1) window(1,2,1)], [window(2,1,1) window(2,2,1)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1,1) window(1,2,1)], [window(2,2,1) window(2,2,1)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1,1) window(1,1,1)], [window(2,1,1) window(2,2,1)],'Color','red','LineStyle','-','Linewidth', 2);

    %SQUARE RADIUS 2 FOR WATER
    text(xcoord(2),ycoord(2),num2str(2),'HorizontalAlignment','center');

    window(:,:,2) = [xcoord(2)-square_radius2 xcoord(2)+square_radius2; ycoord(2)-square_radius2 ycoord(2)+square_radius2]; %EDIT THIS IF YOU NEED TO GO THROUGH MORE
    line([window(1,1,2) window(1,2,2)], [window(2,1,2) window(2,1,2)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,2,2) window(1,2,2)], [window(2,1,2) window(2,2,2)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1,2) window(1,2,2)], [window(2,2,2) window(2,2,2)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1,2) window(1,1,2)], [window(2,1,2) window(2,2,2)],'Color','red','LineStyle','-','Linewidth', 2);
  
end

end %while question == 2

pause(0.5); %Gets rid off random freezing in linux
figure(1);
title(['']); %Removing the title


%Makes a circle mask so other plugs won't get into the SUBIM
% % % % % % [xgrid, ygrid] = meshgrid(1:square_radius*2, 1:square_radius*2);
% % % % % % mask_alt = (xgrid-square_radius).^2 + (ygrid-square_radius).^2 <= (square_radius+buffer).^2;
% % % % % % mask_alt = single(mask_alt);

% TAKING THE VALUES FROM MEDIAN IMAGE

% dicom_median = median(Dicoms,3);

figure; 
% imagesc(dicom_median)

%Determines at what depth we make the analysis
lisaa = 0;
kyssari = 2;
while kyssari == 2
    lisaa = lisaa + 10;
    syvyys = floor(size(Dicoms,3)/4)+lisaa
    imagesc(Dicoms(:,:,syvyys))
    kyssari = menu('Do you see the water??','1) Yes','2) No','3) Again');
    
    if kyssari == 3 
        lisaa = -100;
        kyssari = 2;
    end
end

% Histogram
% % % % % % testia = Dicoms(:,:,syvyys);
% % % % % % figure; hist(testia);

i = 1;
%air = mean2(Dicoms( window(2,1,i):window(2,2,i),  window(1,1,i):window(1,2,i), syvyys));
%air_std = std2(Dicoms( window(2,1,i):window(2,2,i),  window(1,1,i):window(1,2,i), syvyys));
air_matrix(:,:,1) = (Dicoms( window(2,1,i):window(2,2,i),  window(1,1,i):window(1,2,i), syvyys-50)); %maybe there is a better way to do this than to first create a row then add rows via "end+1"...
for ii = (syvyys-49):(syvyys+50)
air_matrix(:,:,end+1) = (Dicoms( window(2,1,i):window(2,2,i),  window(1,1,i):window(1,2,i), ii));
end
air=mean2(air_matrix)
air_std = std2(air_matrix)

i = 2;
%water = mean2(Dicoms( window(2,1,i):window(2,2,i),  window(1,1,i):window(1,2,i), syvyys));
%water_std = std2(Dicoms( window(2,1,i):window(2,2,i),  window(1,1,i):window(1,2,i), syvyys));
water_matrix(:,:,1) = (Dicoms( window(2,1,i):window(2,2,i),  window(1,1,i):window(1,2,i), syvyys-50)); %maybe there is a better way to do this than to first create a row then add rows via "end+1"...
for ii = (syvyys-49):(syvyys+50)
water_matrix(:,:,end+1) = (Dicoms( window(2,1,i):window(2,2,i),  window(1,1,i):window(1,2,i), ii));
end
water=mean2(water_matrix)
water_std = std2(water_matrix)

disp(['-----'])
disp(['Air voxel value: ', num2str(floor(air)), ' +- ', num2str(floor(air_std))]);



disp(['Water voxel value: ', num2str(floor(water)), ' +- ', num2str(floor(water_std))]);
disp(['-----'])


% % % % figure(69)
% % % % plot([air, water], [-1000, 0], 'x')
% % % % ylabel('Hounsfield scale')
% % % % xlabel(['Original scale'])

f = fit([air, water]', [-1000, 0]', 'poly1');

coefficients = [f.p1, f.p2]

    end
%%
    function [SUBIM, xcoord, ycoord] = create_SUBIM(Dicoms,N,xcoord,ycoord)
% EXTRACT SUBIMAGES %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Saves also the subim coordinates [xcoord,ycoord]

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Square size
    % Edit how you like. 
    % 1 pix = 0.036 mm
    % -> 110 pixels equal roughly 8mm diameter
    % -> 100 pixels = 7.2 mm
    square_radius = 50; %80; %110; %Square size 
    buffer = 5; %How much of the figure is cropped from corners
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    % OR USE GETRECT

% % Usual centres of plugs
% xcoord = [364   154   216   515   730];
% ycoord = [705   501   231   157   348];

% Or pick manually %%
question = 2;
while question == 2

pause(0.5); %Gets rid off random freezing in linux
figure(1);

title(['Please pick the center of your plug']);

[xcoord(N), ycoord(N)] = ginput(1); 
xcoord(N) = floor(xcoord(N));
ycoord(N) = floor(ycoord(N));



% Drawing the latest rectangle where the subimages are taken
for i = N
    text(xcoord(i),ycoord(i),num2str(i),'HorizontalAlignment','center');

    window = [xcoord(i)-square_radius xcoord(i)+square_radius; ycoord(i)-square_radius ycoord(i)+square_radius]; %EDIT THIS IF YOU NEED TO GO THROUGH MORE
    line([window(1,1) window(1,2)], [window(2,1) window(2,1)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,2) window(1,2)], [window(2,1) window(2,2)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1) window(1,2)], [window(2,2) window(2,2)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1) window(1,1)], [window(2,1) window(2,2)],'Color','red','LineStyle','-','Linewidth', 2);
end

question = menu('Satisfied?','1) Yes','2) No');

if question == 2
createdicommasks(Dicoms) %Just plotting the figure again
%plots older rectangles again
for i = 1:N-1
    text(xcoord(i),ycoord(i),num2str(i),'HorizontalAlignment','center');

    window = [xcoord(i)-square_radius xcoord(i)+square_radius; ycoord(i)-square_radius ycoord(i)+square_radius]; %EDIT THIS IF YOU NEED TO GO THROUGH MORE
    line([window(1,1) window(1,2)], [window(2,1) window(2,1)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,2) window(1,2)], [window(2,1) window(2,2)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1) window(1,2)], [window(2,2) window(2,2)],'Color','red','LineStyle','-','Linewidth', 2);
    line([window(1,1) window(1,1)], [window(2,1) window(2,2)],'Color','red','LineStyle','-','Linewidth', 2);
end
end

end %while question == 2

%Makes a circle mask so other plugs won't get into the SUBIM
[xgrid, ygrid] = meshgrid(1:square_radius*2, 1:square_radius*2);
mask_alt = (xgrid-square_radius).^2 + (ygrid-square_radius).^2 <= (square_radius+buffer).^2;
mask_alt = uint16(mask_alt);

h = waitbar(0,'Loading subimage, please wait...'); %Display waitbar

%Preallocating to save speed (With 0.7s, without, 0.85s on i5-6267U processor)
SUBIM= uint16(zeros(square_radius*2, square_radius*2, size(Dicoms,3)));

for i = 1:size(Dicoms,3)
    SUBIM(:,:,i) = imcrop(Dicoms(:,:,i),[window(1,1) window(2,1) square_radius*2-1 square_radius*2-1]);
    SUBIM(:,:,i) = SUBIM(:,:,i).*mask_alt;

    waitbar(i/size(Dicoms,3));
end

close(h)
    end

%%
    function dicom_slider(Dicoms,x)
% Function to use slider for image

switch nargin
    case 2
        fig=figure(x); %Uses the same figure 
    case 1
        fig = figure;
end
        
Stack = Dicoms;

koko = size(Stack,3);

%fig=figure;
set(fig,'Name','Image','Toolbar','figure');%,...
    %'NumberTitle','off')
% Create an axes to plot in
axes('Position',[.15 .05 .7 .9]);
% sliders for epsilon and lambda
slider1_handle=uicontrol(fig,'Style','slider','Max',koko,'Min',1,...
    'Value',2,'SliderStep',[1/(koko-1) 10/(koko-1)],...
    'Units','normalized','Position',[.02 .02 .14 .05]);
uicontrol(fig,'Style','text','Units','normalized','Position',[.02 .07 .14 .04],...
    'String','Choose frame');
% Set up callbacks
vars=struct('slider1_handle',slider1_handle,'Stack',Stack);
set(slider1_handle,'Callback',{@slider1_callback,vars});
plotterfcn(vars)
% End of main file

% Callback subfunctions to support UI actions
function slider1_callback(~,~,vars)
    % Run slider1 which controls value of epsilon
    plotterfcn(vars)
end

function plotterfcn(vars)
    % Plots the image
    %imshow(vars.Stack(:,:,round(get(vars.slider1_handle,'Value'))));
    imagesc(vars.Stack(:,:,round(get(vars.slider1_handle,'Value'))));
    axis equal;
    title(num2str(get(vars.slider1_handle,'Value')));
    
end
    end 

%%

    function [dicom_swmask, dicom_swmask_y] = maskcreator(SUBIM)

clear dicom_swmask dicom_swmask_y

h = waitbar(0,'Creating Masks, please wait...'); %Display waitbar
for i = 1:size(SUBIM,1) %y-direction
    for j = 1:size(SUBIM,3) %x-direction
        %Commented can be used to create black and white figures
% % %         if find(SUBIM(i,:,j) > 0) %Look for values above background
% % %             dicom_swmask(j,i,:) = 1;
% % %         else
% % %             dicom_swmask(j,i,:) = 0;
% % %         end
%       Or just take mean
        dicom_swmask(j,i,:) = mean(SUBIM(i,:,j));
    end
end
    
for i = 1:size(SUBIM,2) %y-direction
    for j = 1:size(SUBIM,3) %x-direction    
        %Commented can be used to create black and white figures
% % %         if find(SUBIM(:,i,j) > 0) %Look for values above background
% % %             dicom_swmask_y(j,i,:) = 1;
% % %         else
% % %             dicom_swmask_y(j,i,:) = 0;
% % %         end
        dicom_swmask_y(j,i,:) = mean(SUBIM(:,i,j));
    end 
        waitbar(i/(size(SUBIM,1)));
end
close(h);

% figure(2); %Mask image
% imshow(dicom_swmask)
figure(200)
clf(figure(200))
set(200,'position', [400 200 1200 500]); 
subplot(1,2,1);
% imshow(dicom_swmask);
imagesc(dicom_swmask);
axis equal;
title('From x-direction (Scanco door)');
subplot(1,2,2);
% imshow(dicom_swmask_y);
imagesc(dicom_swmask_y);
axis equal;
title('From y-direction');
    end

%%

    function [ROT_SUBIM] = orientation(SUBIM, dicom_swmask, dicom_swmask_y, slider_question_fororientation)
% Rotating the imagestack  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
figure(200); %Mask image

 %No orientation done
if slider_question_fororientation == 2
   
    for i = 1:size(SUBIM,2)
        for j = 1:size(SUBIM,3)
            SUBIM_x(j,:,i) = SUBIM(:,i,j);
        end
    end
    
    ROT_SUBIM = SUBIM_x;
    rotangle = 0;
    dicom_slider(ROT_SUBIM,98)
end
    
%Orientation is done
if slider_question_fororientation == 1
    

q = 2; % For the while command
direction_question = menu('Which Direction:','1) X','2) Y');


%Create images from different point-of-views
%Based on the answer previously
for i = 1:size(SUBIM,2)
    for j = 1:size(SUBIM,3)
        if direction_question == 1
            SUBIM_x(j,:,i) = SUBIM(:,i,j);
        else
            SUBIM_y(j,:,i) = SUBIM(i,:,j);
        end
    end
end



%Rotating the figure
   while q == 2
       
       % EDIT X-DIRECTION % % % % % % % % % % % % % % % % % % % % % % % % %
       if direction_question == 1 
       figure(200); %Mask image
       subplot(1,2,1);
       pause(0.6); %Gets rid off random freezing in linux
       title('Please pick using your mouse two points in the center, left and right');
       
       %imshow(dicom_swmask)
       imagesc(dicom_swmask)
       axis equal;
       hold on;

       [xrot, yrot] = ginput(2);
       line(xrot,yrot)
       rotangle = atan( (yrot(2)-yrot(1)) / (xrot(2)-xrot(1)) ) * (180/pi); %The angle in degrees
 
       sneakpeak = imrotate(dicom_swmask,rotangle); %Display the mask 
       %Draw lines for comparison
       for i = 1:10:size(Dicoms,2)
         sneakpeak(i,:) = 0;
       end
           
       ROT_SUBIM = imrotate(SUBIM_x,rotangle); %Actual imagestack
       dicom_slider(ROT_SUBIM,98) %Using dicom_slider.m function for viewing
       
       figure(3); 
       %imshow(sneakpeak);
       imagesc(sneakpeak);
       axis equal;

       end
       
       
       
       % EDIT Y-DIRECTION % % % % % % % % % % % % % % % % % % % % % % % % %
       if direction_question == 2
       
             
       figure(200); %Mask image
       subplot(1,2,2);
       pause(0.6); %Gets rid off random freezing in linux
       title('Please pick using your mouse two points in the center, left and right');
       
       %imshow(dicom_swmask_y)
       imagesc(dicom_swmask_y)
       axis equal;
       hold on;

       [xrot, yrot] = ginput(2);
       line(xrot,yrot)
       rotangle = atan( (yrot(2)-yrot(1)) / (xrot(2)-xrot(1)) ) * (180/pi); %The angle in degrees
 
       sneakpeak = imrotate(dicom_swmask_y,rotangle); %Display the mask 
       %Draw lines for comparison
       for i = 1:10:size(Dicoms,2)
         sneakpeak(i,:) = 0;
       end
       
       %This is only from the y-direction
       ROT_SUBIM_Y = imrotate(SUBIM_y,rotangle); %Actual imagestack
       dicom_slider(ROT_SUBIM_Y,98) %Using dicom_slider.m function for viewing
       
       figure(3); 
       %imshow(sneakpeak);
       imagesc(sneakpeak);
       axis equal;

       %Correcting the X-direction
       clear ROT_SUBIM %Needs to be cleared because of the new size
       for i = 1:size(ROT_SUBIM_Y,2)
            for j = 1:size(ROT_SUBIM_Y,3)
                    ROT_SUBIM(:,j,i) = ROT_SUBIM_Y(:,i,j); 
            end
       end
       
       end       
       
              q = menu('Are you satisfied with the angle:','1) Yes','2) No');

   end
end
    end

%%

    function result = calculate_pixelvalues(ROT_SUBIM)
% Calculates averages from slices %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Draws images

% Go slice by slice
clear pixelvalue_average
% Calculate averages for eachs slide
h = waitbar(0,'Creating profile, please wait...'); %Display waitbar
for i = 1:size(ROT_SUBIM,1)
    for j = 1:size(ROT_SUBIM,2)
        pixelvalue_average(j,i,:) = mean(nonzeros(ROT_SUBIM(i,j,:))); % Use only nonzero values
    end
    waitbar(i/size(ROT_SUBIM,1));
end
close(h)
pixelvalue_average = pixelvalue_average'; %Rotation back to normal

slide_average = nanmean(pixelvalue_average,2); %Actual depth-dependent mean for slides


%Displaying and plotting
fig = figure(4);
set(fig,'position', [200 200 1200 500]); 
subplot(1,2,1);
imagesc(pixelvalue_average); 
%colormap hot; 
colorbar;
axis equal;
title('Colormap');
subplot(1,2,2);
plot(slide_average);
title('Full profile');
xlabel('Thickness (px)');
ylabel('Pixel value');

direction_question = 2;
while direction_question == 2


%Show where the bone starts

pause(0.5); %Gets rid off random freezing in linux
figure(4);    
subplot(1,2,1);

title('Click where cartilage begins and ends');

[xcoord, ycoord] = ginput(2);

% xcoord = round(xcoord); Not used
ycoord = round(ycoord);

%Cut the profile
slide_average_new = slide_average(ycoord(1):ycoord(2));

% Remove NaN's and add it into a cell
result = slide_average_new(~isnan(slide_average_new));

%display
figure(5);
plot(result);
title('Profile');
xlabel('Thickness (px)');
ylabel('Pixel value');

direction_question = menu('Satisfied?','1) Yes','2) No');

end %direction_question == 2;

    end

%% 
% Asks if you want to continue

function Thegreatdecider = Ultimatequestion();
    
figure(1) %Show this figure, so you know how many you've done
    
Thegreatdecider = menu('Again?', '1) Yes please, this is great!!!', '2) Please, not anymore :(');

save('DICOM_temp.mat','PROFILES_NORMALIZED') % In case the code crashes

if Thegreatdecider == 2
    %Plot the profiles
    figure(5); %Use existing figure
    plot(PROFILES_NORMALIZED);
    legend_legend = [1:N]';
    legend(num2str(legend_legend),'location','Northwest')
    title('The Profiles')
    xlabel('Normalized thickness (%)');
    ylabel('Pixel value');
    
    figure(1); %Brings the first figure on top
    title('The plugs');
    
    delete 'DICOM_temp.mat' %No need for this if the code executes succesfully
end

end


end













