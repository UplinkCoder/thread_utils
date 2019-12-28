module thread_utils.Thread_utils;

/**
  Splits a string into at most ($D n) nearly equal parts
  cutting after the given delimiter
*/

const(char)[][] splitAfterInto (const(char)[] s, const(char)[] delim, int n)
{
    if (n == 1) return [s];

    const(char)[][] result;
    result.length = n;

    size_t last_split_end = 0;

    const part_length = s.length / n;
    size_t next_split_at = part_length;

    const len_minus_delim_len = s.length - delim.length;

    Loop_outer: foreach(i; 0 .. n)
    {
        if (next_split_at < len_minus_delim_len)
        {
            foreach(p, c; s[next_split_at .. len_minus_delim_len])
            {
                const split_at = next_split_at + p;
                if (c == delim[0] &&  split_at < len_minus_delim_len && s[split_at .. split_at + delim.length] == delim)
                {
                    result[i] = s[last_split_end ..  next_split_at + p + 1];
                    last_split_end = (p + delim.length + next_split_at);

                    next_split_at += part_length;
                    continue Loop_outer;
                }
            }
            goto Lsplit_to_end;
        }
        else
        {
        Lsplit_to_end:
            result[i] = s[last_split_end .. $];
            result = result[0 .. i + 1];
            break Loop_outer;
        }
    }

    {
        size_t empty_idx;
        size_t next_empty_idx;

        foreach(i, part; result)
        {
            if (part.length != 0)
            {
                if (empty_idx)
                {
                    result[empty_idx - 1] = part;
                    result[i] = null;
                    empty_idx = next_empty_idx;
                    next_empty_idx = i + 1;
                }
            }
            else
            {
                result[i] = null;
                if (!empty_idx)
                {
                    if (!next_empty_idx)
                    {
                        empty_idx = i + 1;
                    }
                    else
                    {
                        empty_idx = next_empty_idx;
                        next_empty_idx = i + 1;
                    }
                }
                else if (!next_empty_idx)
                {
                    next_empty_idx =  i + 1;
                }
            }
        }

        if (empty_idx)
        {
            foreach_reverse(i, part; result[0 .. empty_idx])
            {
                if (part)
                {
                    empty_idx -= (i + 1);
                    break;
                }
            }
            result = result[0 .. empty_idx];
        }
    }

    assert(() {
        size_t combined_length;
        foreach(part;result)
        {
            combined_length += part.length;
        }
        return combined_length == s.length;
    } ());

    return result;
}

static assert ("aaavbbbvcccvddv".splitAfterInto("v", 2) == ["aaavbbbv", "cccvddv"]);
static assert ("aaavbbbvcccvddv".splitAfterInto("v", 3) == ["aaavbbbv", "cccv", "ddv"]);
static assert ("aaavbbbvcccvddv".splitAfterInto("v", 4) == ["aaav", "bbbv", "cccv", "ddv"]);
static assert ("aaavbbbvcccvddv".splitAfterInto("v", 12) == ["aaav", "bbbv", "cccv", "ddv"]);

