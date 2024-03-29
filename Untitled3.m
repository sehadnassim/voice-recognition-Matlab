clear all
close all
% Load two speech waveforms of the same utterance (from TIMIT)
[fname,fpath]=uigetfile('*.wav');    %selection du fichier audio a ecouter
[d1,sr]=audioread([fpath,fname]);  
[fname,fpath]=uigetfile('*.wav');    %selection du fichier audio a ecouter
[d2,sr]=audioread([fpath,fname]);  
 
 % Listen to them together:
 ml = min(length(d1),length(d2));
 soundsc(d1(1:ml)+d2(1:ml),sr)
 % or, in stereo
 soundsc([d1(1:ml),d2(1:ml)],sr)

 % Calculate STFT features for both sounds (25% window overlap)
 D1 = specgram(d1,512,sr,512,384);
 D2 = specgram(d2,512,sr,512,384);

 % Construct the 'local match' scores matrix as the cosine distance 
 % between the STFT magnitudes
 ED1 = sqrt(sum((abs(D1)).^2));
 ED2 = sqrt(sum((abs(D2)).^2));
 SM = ((abs(D1))'*(abs(D2)))./(ED1'*ED2);
%%%%%%%%%%  SM = simmx(abs(D1),abs(D2));
 % Look at it:
 subplot(121)
 imagesc(SM)
 colormap(1-gray)
 % You can see a dark stripe (high similarity values) approximately
 % down the leading diagonal.

 % Use dynamic programming to find the lowest-cost path between the 
 % opposite corners of the cost matrix
 % Note that we use 1-SM because dp will find the *lowest* total cost
 M=1-SM;
 [r,D2x] = size(M);

% costs
C = zeros(r+1, D2x+1);
C(1,:) = NaN;
C(:,1) = NaN;
C(1,1) = 0;
C(2:(r+1), 2:(D2x+1)) = M;

% traceback
phi = zeros(r,D2x);

for i = 1:r; 
  for j = 1:D2x;
    [dmax, tb] = min([C(i, j), C(i, j+1), C(i+1, j)]);
    C(i+1,j+1) = C(i+1,j+1)+dmax;
    phi(i,j) = tb;
  end
end

% Traceback from top left
i = r; 
j = D2x;
p = i;
q = j;
while i > 1 & j > 1
  tb = phi(i,j);
  if (tb == 1)
    i = i-1;
    j = j-1;
  elseif (tb == 2)
    i = i-1;
  elseif (tb == 3)
    j = j-1;
  else    
    error;
  end
  p = [i,p];
  q = [j,q];
end

% Strip off the edges of the D matrix before returning
C = C(2:(r+1),2:(D2x+1));
 %%%%%%%%%%[p,q,C] = dp(1-SM);
 % Overlay the path on the local similarity matrix
 hold on; plot(q,p,'r');title('signal A');ylabel('signal B'); hold off 
 % Path visibly follows the dark stripe
 
 % Plot the minimum-cost-to-this point matrix too
 subplot(122)
 imagesc(C)
 hold on; plot(q,p,'r');title('signal A');ylabel('signal B'); hold off
%[image of DTW path]
 
 % Bottom right corner of C gives cost of minimum-cost alignment of the two
 n=C(size(C,1),size(C,2))

 % This is the value we would compare between different 
 % templates if we were doing classification.
 
 % Calculate the frames in D2 that are indicated to match each frame
 % in D1, so we can resynthesize a warped, aligned version
 D2i1 = zeros(1, size(D1,2));
 for i = 1:length(D2i1); D2i1(i) = q(min(find(p >= i))); end
 % Phase-vocoder interpolate D2's STFT under the time warp
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[rows,cols] = size(D2);

N = 2*(rows-1);
t=D2i1-1;
% Empty output array
D2x = zeros(rows, length(t));

% Expected phase advance in each bin
dphi = zeros(1,N/2+1);
dphi(2:(1 + N/2)) = (2*pi*128)./(N./(1:(N/2)));

% Phase accumulator
% Preset to phase of first frame for perfect reconstruction
% in case of 1:1 time scaling
ph = angle(D2(:,1));

% Append a 'safety' column on to the end of b to avoid problems 
% taking *exactly* the last frame (i.e. 1*b(:,cols)+0*b(:,cols+1))
D2 = [D2,zeros(rows,1)];

ocol = 1;
for tt = t
  % Grab the two columns of b
  bcols = D2(:,floor(tt)+[1 2]);
  tf = tt - floor(tt);
  bmag = (1-tf)*abs(bcols(:,1)) + tf*(abs(bcols(:,2)));
  % calculate phase advance
  dp = angle(bcols(:,2)) - angle(bcols(:,1)) - dphi';
  % Reduce to -pi:pi range
  dp = dp - 2 * pi * round(dp/(2*pi));
  % Save the column
  D2x(:,ocol) = bmag .* exp(j*ph);
  % Cumulate phase, ready for next frame
  ph = ph + dphi' + dp;
  ocol = ocol+1;
end
 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%D2x = pvsample(D2, D2i1-1, 128);
 % Invert it back to time domain
 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ftsize= 512;
w = 512;
h = 128; 

s = size(D2x);
if s(1) ~= (ftsize/2)+1
  error('number of rows should be fftsize/2+1')
end
cols = s(2);
 
if length(w) == 1
  if w == 0
    % special case: rectangular window
    win = ones(1,ftsize);
  else
    if rem(w, 2) == 0   % force window to be odd-len
      w = w + 1;
    end
    halflen = (w-1)/2;
    halff = ftsize/2;
    halfwin = 0.5 * ( 1 + cos( pi * (0:halflen)/halflen));
    win = zeros(1, ftsize);
    acthalflen = min(halff, halflen);
    win((halff+1):(halff+acthalflen)) = halfwin(1:acthalflen);
    win((halff+1):-1:(halff-acthalflen+2)) = halfwin(1:acthalflen);
    % 2009-01-06: Make stft-istft loop be identity for 25% hop
    win = 2/3*win;
  end
else
  win = w;
end

w = length(win);
% now can set default hop
if h == 0 
  h = floor(w/2);
end

xlen = ftsize + (cols-1)*h;
d2x = zeros(1,xlen);

for b = 0:h:(h*(cols-1))
  ft = D2x(:,1+b/h)';
  ft = [ft, conj(ft([((ftsize/2)):-1:2]))];
  px = real(ifft(ft));
  d2x((b+1):(b+ftsize)) = d2x((b+1):(b+ftsize))+px.*win;
end;
 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%d2x = istft(D2x, 512, 512, 128);

 % Listen to the results
 % Warped version alone
 soundsc(d2x,sr)
 % Warped version added to original target (have to fine-tune length)
 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
 d2x = zeros(length(d1),1);
 B=d2x' ;
[v,c] = size(B);

mr = min(v,length(d1));
mc = min(c,1);

d2x(1:mr,1:mc) = B(1:mr, 1:mc);

 %%%%%%%%%%%%%%%%%%%%%%%%%d2x = resize(d2x', length(d1),1);
 soundsc(d1+d2x,sr)
 % .. and in stereo
 soundsc([d1,d2x],sr)
 % Compare to unwarped pair:
 soundsc([d1(1:ml),d2(1:ml)],sr)
 
 thingSpeakWrite(873996,n,'WriteKey','31GWWLD6JNC14UET')