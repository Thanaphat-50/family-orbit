<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SocialAccount extends Model
{
    public const PROVIDERS = ['google', 'line', 'facebook'];

    public const LABELS = [
        'google' => 'Google',
        'line' => 'LINE',
        'facebook' => 'Facebook',
    ];

    protected $fillable = [
        'user_id',
        'provider',
        'provider_user_id',
        'email',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
