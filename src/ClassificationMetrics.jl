using LinearAlgebra
using Statistics

forceMatrix(a) = (length(size(a)) == 1) ? reshape( a, length(a), 1 ) : a

function IsColdEncoded(Y)
    return size( forceMatrix( Y ) )[2] == 1
end

struct ClassificationLabel
    ToHot::Dict
    ToCold::Dict
    LabelCount::Int
end

function LabelEncoding(HotOrCold)
    HotOrCold = forceMatrix(HotOrCold)
    if IsColdEncoded(HotOrCold)
        Lbls = unique(HotOrCold)
    else
        Lbls = (1:size(HotOrCold)[2])
    end
    return ClassificationLabel(Dict( Lbls .=> collect(1 : length(Lbls) ) ),
                                Dict( collect(1 : length(Lbls)) .=> Lbls ),
                                length(Lbls) )
end


function ColdToHot(Y, Schema::ClassificationLabel)
    lenY = length( Y )
    Output = zeros( lenY, Schema.LabelCount )
    for y in 1 : lenY
        Output[y, Schema.ToHot[ Y[y] ] ] = 1
    end
    return Output
end

function HotToCold(Y, Schema::ClassificationLabel)
    Y = forceMatrix(Y)
    (lenY, Feats) = size( Y )
    @assert Feats == Schema.LabelCount
    Output = zeros( lenY )
    for y in 1 : lenY
        Output[ y ] =  Schema.ToCold[ findfirst( x -> x == 1, Y[ y , : ] ) ]
    end
    return Output
end

#Y and GT are one cold encodings...
#Cold : Some 1-array of unique class labels
#Hot : Some 2-array where each unique label has a columns
#HighestVote : Takes some 2 array and makes it fit a Hot Schema

#If I have voted hot scheme but want absolute accuracies what do I do?
#    Well.. what do we start with..

#Cold -> Hot
# => GT is Cold
#   So we want the Hot Label for GT to designate columns in confusion matrix..
#What if someone puts a hot GT in?
#   we want to highest vote it I guess? Simple...
#Say Y is Hot encoded...
#  We want highest vote, easy again...

function MulticlassStats(Y, GT, schema; Microaverage = true)
    Y = forceMatrix(Y)
    GT = forceMatrix(GT)
    Y = IsColdEncoded(Y) ?  map(x -> Int(schema.ToHot[ x ]), Y) : HighestVote(Y)
    GT = IsColdEncoded(GT) ? map(x -> Int(schema.ToHot[ x ]), GT) : HighestVote(GT)
    @assert(size(Y)[1] == size(GT)[1])
    ConfusionMatrix = zeros( schema.LabelCount, schema.LabelCount )
    for y in 1 : size(Y)[1]
        ConfusionMatrix[ Y[ y ], GT[ y ] ] += 1
    end
    TP = repeat( [0], schema.LabelCount ) ; TN = repeat( [0], schema.LabelCount )
    FP = repeat( [0], schema.LabelCount ) ; FN = repeat( [0], schema.LabelCount )
    for c in 1 : schema.LabelCount
        TP[c] = ConfusionMatrix[c,c]
        FP[c] = sum(ConfusionMatrix[:,c]) - TP[c]
        FN[c] = sum(ConfusionMatrix[c,:]) - TP[c]
        TN[c] = sum(ConfusionMatrix) - TP[c] - FP[c] - FN[c]
    end

    if Microaverage
        TP = StatsBase.mean(TP); TN = StatsBase.mean(TN)
        FP = StatsBase.mean(FP); FN = StatsBase.mean(FN)
        Precision = TP / ( TP + FP )
        Recall = TP / ( TP + FN )
        Sensitivity = TP / ( TP + FN )
        Specificity = TN / ( TN + FP )
        Accuracy = ( TP + TN ) / ( TP + TN + FP + FN )
        FMeasure = 2.0 * ( ( Precision * Recall ) / ( Precision + Recall ) )
        FAR = FP / ( FP + TN )
        FNR = FN / ( FN + TP )
        return Dict("ConfusionMatrix" => ConfusionMatrix,
                    "TP" => TP, "FP" => FP, "TN" => TN, "FN" => FN,
                    "Sensitivity" => Sensitivity,   "Specificity" => Specificity,
                    "Precision" => Precision,       "Recall" => Recall,
                    "Accuracy" => Accuracy,         "FMeasure" => FMeasure,
                    "FAR" => FAR,                   "FNR" => FNR )
    else #Macro Average
        Precision = StatsBase.mean(TP ./ ( TP .+ FP ))
        Recall = StatsBase.mean(TP ./ ( TP .+ FN ))
        Sensitivity = StatsBase.mean(TP ./ ( TP .+ FN ))
        Specificity = StatsBase.mean(TN ./ ( TN .+ FP ))
        Accuracy = StatsBase.mean(( TP .+ TN ) ./ ( TP .+ TN .+ FP .+ FN ))
        FMeasure = StatsBase.mean(2.0 .* ( ( Precision .* Recall ) ./ ( Precision .+ Recall ) ))
        FAR = StatsBase.mean(FP ./ ( FP .+ TN ))
        FNR = StatsBase.mean(FN ./ ( FN .+ TP ))
        return Dict("ConfusionMatrix" => ConfusionMatrix,
                    "TP" => TP, "FP" => FP, "TN" => TN, "FN" => FN,
                    "Sensitivity" => Sensitivity,   "Specificity" => Specificity,
                    "Precision" => Precision,       "Recall" => Recall,
                    "Accuracy" => Accuracy,         "FMeasure" => FMeasure,
                    "FAR" => FAR,                   "FNR" => FNR )
    end
end

#Voting Schemes
Threshold(yhat; level = 0.5) = map( y -> (y >= level) ? 1 : 0, yhat)

#Warning this function can allow for no class assignments...
function MulticlassThreshold(yhat; level = 0.5)
    newY = zeros(size(yhat))
    for obs in 1 : size(yhat)[1]
        (val, ind) = findmax( yhat[obs,:] )
        if val > level
            newY[ind] = val
        end
    end
    return newY
end

function HighestVote(yhat)
    return [ findmax( yhat[obs,:] )[2] for obs in 1 : size(yhat)[1]  ]
end