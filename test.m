% -----------------------------------------------------------------------
% This file is part of the ASTRA Toolbox
% 
% Copyright: 2010-2016, iMinds-Vision Lab, University of Antwerp
%            2014-2016, CWI, Amsterdam
% License: Open Source under GPLv3
% Contact: astra@uantwerpen.be
% Website: http://www.astra-toolbox.com/
% -----------------------------------------------------------------------

% This sample illustrates the use of opTomo.
%
% opTomo is a wrapper around the FP and BP operations of the ASTRA Toolbox,
% to allow you to use them as you would a matrix.
%
% This class requires the Spot Linear-Operator Toolbox to be installed.
% You can download this at http://www.cs.ubc.ca/labs/scl/spot/

startup

global fIter 
path    = strcat(pwd,'/results_paper/modelD/');
fIter   = 1;
mtype   = 4;
noise   = 0;

%% load a phantom image
if (mtype==1)
    n = 256; mtype1 = 1; rseed = 1; bgmax = 0.5;
elseif (mtype==2)
    n = 128; mtype1 = 2; rseed = 5; bgmax = 0.5;
elseif (mtype==3)
    n = 256; mtype1 = 1; rseed = 10; bgmax = 0.75;
elseif (mtype==4)
    n = 128; mtype1 = 2; rseed = 20; bgmax = 0.75;
end


modelOpt.xwidth     = 0.6;
modelOpt.zwidth     = 0.4;
modelOpt.nrand      = 50;
modelOpt.randi      = 6;
modelOpt.bg.smooth  = 10;
modelOpt.bg.bmax    = bgmax;
modelOpt.type       = mtype1;
modelOpt.rseed      = rseed;



[im,bgIm]   = createPhantom(0:1/(n-1):1,0:1/(n-1):1,modelOpt); % object of size 256 x 256
x           = im(:);

fig1 = figure(1); imagesc(im,[0 1]); axis equal tight; axis off;
saveas(fig1,strcat(path,'model',num2str(mtype)),'epsc');
saveas(fig1,strcat(path,'model',num2str(mtype)),'fig');

imV = im(:);
imshape = zeros(size(imV));
imshape(imV == 1) = 1;

%% Setting up the geometry
% projection geometry
proj_geom = astra_create_proj_geom('parallel', 1, n, linspace2(0,2*pi/3,5));

% object dimensions
vol_geom  = astra_create_vol_geom(n,n);


%% Generate projection data
% Create the Spot operator for ASTRA using the GPU.
W   = opTomo('cuda', proj_geom, vol_geom);

W0  = opTomo('line', proj_geom, vol_geom);
p   = W0*x;

% adding noise to data
if noise
    pN = addwgn(p,10,0);
else
    pN = p;
end

% reshape the vector into a sinogram
sinogram = reshape(p, W.proj_size);  
sinogramN= reshape(pN, W.proj_size); % look at how noise has been added

%% Reconstruction - LSQR
% We use a least squares solver lsqr from Matlab to solve the 
% equation W*x = p.
% Max number of iterations is 100, convergence tolerance of 1e-6.
[x_ls]  = lsqr(W, pN, 1e-6, 5000);
rec_ls  = reshape(x_ls, W.vol_size);
res_ls  = norm(rec_ls(:) - im(:));

fig2 = figure(2);
imagesc(rec_ls,[0 1]); axis equal tight; axis off;% imshow(reconstruction, []);
saveas(fig1,strcat(path,'m',num2str(mtype),'_lsqr_n',num2str(noise)),'epsc');
saveas(fig1,strcat(path,'m',num2str(mtype),'_lsqr_n',num2str(noise)),'fig')

LS.rec              = rec_ls;
LS.shape            = zeros(size(x_ls));
LS.shape(x_ls >= 1) = 1;
LS.modRes           = norm(x_ls - im(:));
LS.diff             = LS.shape - imshape;
LS.shapeRes         = sum(abs(LS.diff));
LS.dataRes          = norm(W*x_ls - pN);

fprintf('\n LSQR Method: ModelResidual = %0.2d and ShapeResidual =  %0.2d DataResidual = %0.2d \n',LS.modRes,LS.shapeRes,LS.dataRes);

%% Reconstruction with parametric level-set method
% We use a joint reconstruction method to solve the 
% equation W*x = p.
% jointRec(W,p,lambda,kappa,maxIter,iPstr)
kappa               = 0.05;
maxIter             = 50;
maxInnerIter        = 250;

newMethod.run       = 0;
newMethod.maxLoop   = 10;
newMethod.changeL   = 1;
newMethod.changeHW  = 1;
newMethod.maxIter   = 20;
newMethod.recFactL  = 0.1;
newMethod.recFactHW = 0.9;
ipStr.newMethod     = newMethod;

fig.show            = 0;
fig.save            = 0;
fig.path            = path;
ipStr.fig           = fig;

imV                 = im(:);
imshape             = zeros(size(imV));
imshape(imV == 1)   = 1;

lambda              = 5e5;
    
[x_pls,Op]  = jointRec(W,pN,lambda,kappa,maxIter,maxInnerIter,ipStr);
rec_pls     = reshape(x_pls, W.vol_size);

fig3 = figure(3);
imagesc(rec_pls,[0 1]); axis equal tight; axis off;
saveas(fig3,strcat(path,'m',num2str(mtype),'_pls_n',num2str(noise)),'epsc');
saveas(fig3,strcat(path,'m',num2str(mtype),'_pls_n',num2str(noise)),'fig')

PLS.rec                 = rec_pls;
PLS.shape               = zeros(size(x_pls));
PLS.shape(x_pls >= 1)   = 1;
PLS.modRes              = norm(x_pls - im(:));
PLS.diff                = PLS.shape - imshape;
PLS.shapeRes            = sum(abs(PLS.diff));
PLS.dataRes             = norm(W*x_pls - pN);

fprintf('\n PLS Method: ModelResidual = %0.2d and ShapeResidual =  %0.2d DataResidual = %0.2d \n',PLS.modRes,PLS.shapeRes,PLS.dataRes);


%% Total Variation
TVOp    = opTV(n);
scale   = 0.0796;

x_tv    = chambollePock(scale*W, TVOp, pN, 200, 1.9, true, [], 1);   % lambda = 1.9 best MR, = 2.683 best SR
x_tv    = scale*x_tv;
rec_tv  = reshape(x_tv, W.vol_size);

fig4 = figure(4);
imagesc(rec_tv,[0 1]); axis equal tight; axis off;
saveas(fig4,strcat(path,'m',num2str(mtype),'_tv_n',num2str(noise)),'epsc');
saveas(fig4,strcat(path,'m',num2str(mtype),'_tv_n',num2str(noise)),'fig')

TV.rec              = rec_tv;
TV.shape            = zeros(size(x_tv));
TV.shape(x_tv >= 1) = 1;
TV.modRes           = norm(x_tv - im(:));
TV.diff             = TV.shape - imshape;
TV.shapeRes         = sum(abs(TV.diff));
TV.dataRes          = norm(W*x_tv - pN);

fprintf('\n Total Variation Method: ModelResidual = %0.2d and ShapeResidual =  %0.2d DataResidual = %0.2d \n',TV.modRes,TV.shapeRes,TV.dataRes);

%% DART

greyValues      = [linspace(0,0.5,20) 1]'; % unique(im);
initial_arm_it  = 40;
arm_it          = 100;
dart_it         = 100;

x_dart      = astra.dart(sinogram(:), proj_geom, vol_geom, greyValues, initial_arm_it, ...
            arm_it, dart_it, 'SIRT_CUDA', 0.99, [], im);
x_dart      = x_dart(:);
rec_dart    = reshape(x_dart, W.vol_size);

fig5 = figure(5);
imagesc(rec_dart,[0 1]); axis equal tight; axis off;
saveas(fig5,strcat(path,'m',num2str(mtype),'_dart_n',num2str(noise)),'epsc');
saveas(fig5,strcat(path,'m',num2str(mtype),'_dart_n',num2str(noise)),'fig')

DART.rec                = rec_dart;
DART.shape              = zeros(size(x_dart));
DART.shape(x_dart >= 1) = 1;
DART.modRes             = norm(x_dart - im(:));
DART.diff               = DART.shape - imshape;
DART.shapeRes           = sum(abs(DART.diff));
DART.dataRes            = norm(W*x_dart - pN);

fprintf('\n DART Method: ModelResidual = %0.2d and ShapeResidual =  %0.2d DataResidual = %0.2d \n',DART.modRes,DART.shapeRes,DART.dataRes);


%% saving

save(strcat(path,'results',num2str(noise),'.mat'),'LS','PLS','TV','DART');

