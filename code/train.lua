local image = require 'image'
local optim = require 'optim'

local M = {}
local Trainer = torch.class('sr.Trainer', M)

function Trainer:__init(model, criterion, opt)
    self.model = model
    self.tempModel = nil
    self.criterion = criterion

    self.opt = opt
    self.optimState = opt.optimState
    self.scale = opt.scale

    self.iter = opt.lastIter        --Total iterations
    self.err = 0

    self.input = nil
    self.target = nil
    self.params = nil
    self.gradParams = nil

    self.feval = function() return self.errB, self.gradParams end
    self.util = require 'utils'(opt)

    self.retLoss, self.retPSNR = nil, nil
    self.maxPerf, self.maxIdx = {}, {}
    for i = 1, #self.scale do
        table.insert(self.maxPerf, -1)
        table.insert(self.maxIdx, -1)
    end
end

function Trainer:train(epoch, dataloader)
    local size = dataloader:size()
    local trainTimer = torch.Timer()
    local dataTimer = torch.Timer()
    local trainTime, dataTime = 0, 0
    local globalIter, globalErr, localErr = 0, 0, 0

    local pe = self.opt.printEvery
    local te = self.opt.testEvery

    cudnn.fastest = true
    cudnn.benchmark = true

    self.model:clearState()
    self.model:cuda()
    self:prepareSwap('cuda')
    self.model:training()
    self:getParams()
    collectgarbage()
    collectgarbage()

    for n, batch in dataloader:run() do
        dataTime = dataTime + dataTimer:time().real
        self:copyInputs(batch.input, batch.target, 'train')
        local sci = batch.scaleR

        self.model:zeroGradParameters()
        --Fast model swap
        self.tempModel = self.model
        self.model = self.swapTable[sci]

        self.model:forward(self.input)
        self.criterion(self.model.output, self.target)
        self.model:backward(self.input, self.criterion.gradInput)
        --Return to original model
        self.model = self.tempModel
        
        self.iter = self.iter + 1
        self.err = self.criterion.output
        globalIter = globalIter + 1
        globalErr = globalErr + self.criterion.output
        localErr = localErr + self.criterion.output

        if self.opt.clip > 0 then
            self.gradParams:clamp(-self.opt.clip / self.opt.lr, self.opt.clip / self.opt.lr)
        end
        self.optimState.method(self.feval, self.params, self.optimState)
        trainTime = trainTime + trainTimer:time().real
        
        if n % pe == 0 then
            local lr_f, lr_d = self:getlr()
            print(('[Iter: %.1fk - lr: %.2fe%d]\tTime: %.2f (Data: %.2f)\tErr: %.6f')
                :format(self.iter / 1000, lr_f, lr_d, trainTime, dataTime, localErr / pe))
            localErr, trainTime, dataTime = 0, 0, 0
        end

        trainTimer:reset()
        dataTimer:reset()

        if n % te == 0 then
            break
        end
    end

    if epoch % self.opt.manualDecay == 0 then
        local prevlr = self.optimState.learningRate
        self.optimState.learningRate = prevlr / 2
        print(('Learning rate decreased: %.6f -> %.6f')
            :format(prevlr, self.optimState.learningRate))
    end

    self.retLoss = globalErr / globalIter
end

function Trainer:test(epoch, dataloader)
    --Code for multiscale learning
    local timer = torch.Timer()
    local iter, avgPSNR = 0, {}
    for i = 1, #self.scale do
        table.insert(avgPSNR, 0)
    end

    cudnn.fastest = false
    cudnn.benchmark = false

    self.model:clearState()
    self.model:float()
    self:prepareSwap('float')
    self.model:evaluate()
    collectgarbage()
    collectgarbage()
    
    for n, batch in dataloader:run() do
        for i = 1, #self.scale do
            local sc = self.scale[i]
            self:copyInputs(batch.input[i], batch.target[i], 'train')

            local input = nn.Unsqueeze(1):cuda():forward(self.input)
            if self.opt.nChannel == 1 then
                input = nn.Unsqueeze(1):cuda():forward(input)
            end
            
            --Fast model swap
            self.tempModel = self.model
            self.model = self.swapTable[i]

            local output = self.util:recursiveForward(input, self.model, self.opt.safe)
            
            --Return to original model
            self.model = self.tempModel

            if self.opt.selOut > 0 then
                output = output[selOut]
            end

            output = output:squeeze(1)
            self.util:quantize(output, self.opt.mulImg)
            self.target:div(self.opt.mulImg)
            avgPSNR[i] = avgPSNR[i] + self.util:calcPSNR(output, self.target, sc)

            image.save(paths.concat(self.opt.save, 'result', n .. '_X' .. sc .. '.png'), output) 

            iter = iter + 1
            
            self.model:clearState()
            self.input = nil
            self.target = nil
            output = nil
            collectgarbage()
            collectgarbage()
        end
        batch = nil
        collectgarbage()
        collectgarbage()
    end
    print(('epoch %d (iter/epoch: %d)] Test time: %.2f')
        :format(epoch, self.opt.testEvery, timer:time().real))

    for i = 1, #self.scale do
        avgPSNR[i] = avgPSNR[i] * #self.scale / iter
        if avgPSNR[i] > self.maxPerf[i] then
            self.maxPerf[i] = avgPSNR[i]
            self.maxIdx[i] = epoch
        end
        print(('Average PSNR: %.4f (X%d) / Highest PSNR: %.4f (X%d) - epoch %d')
            :format(avgPSNR[i], self.scale[i], self.maxPerf[i], self.scale[i], self.maxIdx[i]))
    end
    print('')
    
    self.retPSNR = avgPSNR
end

function Trainer:copyInputs(input, target, mode)
    if mode == 'train' then
        self.input = self.input or (self.opt.nGPU == 1 and torch.CudaTensor() or cutorch.createCudaHostTensor())
    elseif mode == 'test' then
        self.input = self.input or torch.CudaTensor()
    end
    self.target = self.target or torch.CudaTensor()

    self.input:resize(input:size()):copy(input)
    self.target:resize(target:size()):copy(target)

    input = nil
    target = nil
    collectgarbage()
    collectgarbage()
end

function Trainer:getlr()
    local logLR = math.log(self.optimState.learningRate, 10)
    local characteristic = math.floor(logLR)
    local mantissa = logLR - characteristic
    local frac = math.pow(10,mantissa)

    return frac, characteristic
end

function Trainer:getParams()
    self.params, self.gradParams = self.model:getParameters()
end

function Trainer:prepareSwap(modelType)
    self.swapTable = {}
    for i = 1, #self.scale do
        local swapped = self.util:swapModel(self.model, i)
        if modelType == 'float' then
            swapped = swapped:float()
        elseif modelType == 'cuda' then
            swapped = swapped:cuda()
        end
        table.insert(self.swapTable, swapped)
    end
end

function Trainer:updateLoss(loss)
    table.insert(loss, {key = self.iter, value = self.retLoss})

    return loss
end

function Trainer:updatePSNR(psnr)
    for i = 1, #self.scale do
        table.insert(psnr[i], {key = self.iter, value = self.retPSNR[i]})
    end

    return psnr
end

return M.Trainer
